#include "datafilespage.hpp"
#include "maindialog.hpp"

#include <archive.h>
#include <archive_entry.h>

#include <QBrush>
#include <QClipboard>
#include <QCoreApplication>
#include <QColor>
#include <QAbstractItemView>
#include <QDebug>
#include <QDesktopServices>
#include <QDateTime>
#include <QDialogButtonBox>
#include <QEventLoop>
#include <QDirIterator>
#include <QFile>
#include <QFileDialog>
#include <QHash>
#include <QHBoxLayout>
#include <QImageReader>
#include <QInputDialog>
#include <QJsonDocument>
#include <QJsonArray>
#include <QJsonObject>
#include <QJsonParseError>
#include <QLabel>
#include <QHeaderView>
#include <QList>
#include <QLineEdit>
#include <QLocale>
#include <QMessageBox>
#include <QNetworkAccessManager>
#include <QNetworkReply>
#include <QNetworkRequest>
#include <QPair>
#include <QProgressDialog>
#include <QProcess>
#include <QRegularExpression>
#include <QSaveFile>
#include <QPushButton>
#include <QSet>
#include <QSettings>
#include <QSignalBlocker>
#include <QStandardPaths>
#include <QSize>
#include <QTableWidget>
#include <QTemporaryDir>
#include <QTemporaryFile>
#include <QTimer>
#include <QUrl>
#include <QUrlQuery>
#include <QUuid>
#include <QVBoxLayout>

#include <algorithm>
#include <limits>
#include <mutex>
#include <thread>
#include <unordered_set>

#include <apps/launcher/utils/cellnameloader.hpp>

#include <components/files/configurationmanager.hpp>

#include <components/contentselector/model/esmfile.hpp>
#include <components/contentselector/view/contentselector.hpp>

#include <components/config/gamesettings.hpp>
#include <components/config/launchersettings.hpp>

#include <components/bsa/compressedbsafile.hpp>
#include <components/debug/debuglog.hpp>
#include <components/files/qtconversion.hpp>
#include <components/misc/strings/conversion.hpp>
#include <components/navmeshtool/protocol.hpp>
#include <components/settings/values.hpp>
#include <components/vfs/bsaarchive.hpp>
#include <components/vfs/qtconversion.hpp>

#include "utils/profilescombobox.hpp"
#include "utils/textinputdialog.hpp"

const char* Launcher::DataFilesPage::mDefaultContentListName = "Default";

namespace
{
    const QString& nxmDesktopEntryId()
    {
        static const QString id = QStringLiteral("openmw-morrowindpl-nxm.desktop");
        return id;
    }

    QString nxmHandlerExecutablePath()
    {
#ifdef Q_OS_LINUX
        const QString appImage = QString::fromLocal8Bit(qgetenv("APPIMAGE")).trimmed();
        if (!appImage.isEmpty())
            return QFileInfo(appImage).absoluteFilePath();
#endif
        return QFileInfo(QCoreApplication::applicationFilePath()).absoluteFilePath();
    }

    QString desktopExecValue(QString executable)
    {
        executable.replace(QLatin1Char('\\'), QStringLiteral("\\\\"));
        executable.replace(QLatin1Char('"'), QStringLiteral("\\\""));
        executable.replace(QLatin1Char('`'), QStringLiteral("\\`"));
        executable.replace(QLatin1Char('$'), QStringLiteral("\\$"));
        executable.replace(QLatin1Char('%'), QStringLiteral("%%"));
        // %u is the Desktop Entry field code for one URL. Only literal
        // percent signs that belong to the executable path must be escaped.
        return QStringLiteral("\"%1\" %u").arg(executable);
    }

    QString readDefaultHandlerFromMimeapps(const QString& path)
    {
        QFile file(path);
        if (!file.open(QIODevice::ReadOnly | QIODevice::Text))
            return {};

        const QStringList lines
            = QString::fromUtf8(file.readAll()).split(QLatin1Char('\n'));
        bool inDefaults = false;

        for (QString line : lines)
        {
            line = line.trimmed();
            if (line.startsWith(QLatin1Char('[')) && line.endsWith(QLatin1Char(']')))
            {
                inDefaults = line.compare(
                    QStringLiteral("[Default Applications]"), Qt::CaseInsensitive) == 0;
                continue;
            }

            if (!inDefaults || line.startsWith(QLatin1Char('#'))
                || line.startsWith(QLatin1Char(';')))
                continue;

            const int equals = line.indexOf(QLatin1Char('='));
            if (equals <= 0)
                continue;

            if (line.left(equals).trimmed().compare(
                    QStringLiteral("x-scheme-handler/nxm"), Qt::CaseInsensitive) != 0)
                continue;

            const QStringList handlers
                = line.mid(equals + 1).split(QLatin1Char(';'), Qt::SkipEmptyParts);
            if (!handlers.isEmpty())
                return handlers.constFirst().trimmed();
        }

        return {};
    }

    QString fallbackNxmHandlerDesktopId()
    {
#ifdef Q_OS_LINUX
        QString configHome = QString::fromLocal8Bit(qgetenv("XDG_CONFIG_HOME")).trimmed();
        if (configHome.isEmpty())
            configHome = QStandardPaths::writableLocation(QStandardPaths::ConfigLocation);

        QString dataHome = QString::fromLocal8Bit(qgetenv("XDG_DATA_HOME")).trimmed();
        if (dataHome.isEmpty())
            dataHome = QStandardPaths::writableLocation(QStandardPaths::GenericDataLocation);

        QStringList candidates;
        if (!configHome.isEmpty())
            candidates << QDir(configHome).filePath(QStringLiteral("mimeapps.list"));
        if (!dataHome.isEmpty())
            candidates << QDir(dataHome).filePath(QStringLiteral("applications/mimeapps.list"));
        candidates << QStringLiteral("/usr/local/share/applications/mimeapps.list")
                   << QStringLiteral("/usr/share/applications/mimeapps.list");

        for (const QString& path : candidates)
        {
            const QString handler = readDefaultHandlerFromMimeapps(path);
            if (!handler.isEmpty())
                return handler;
        }
#endif
        return {};
    }

    QString currentNxmHandlerDesktopId()
    {
#ifdef Q_OS_LINUX
        const QString gio = QStandardPaths::findExecutable(QStringLiteral("gio"));
        if (!gio.isEmpty())
        {
            QProcess process;
            process.start(gio, { QStringLiteral("mime"), QStringLiteral("x-scheme-handler/nxm") });
            if (process.waitForFinished(3000) && process.exitStatus() == QProcess::NormalExit)
            {
                const QString output = QString::fromUtf8(
                    process.readAllStandardOutput() + process.readAllStandardError());
                const QStringList lines
                    = output.split(QLatin1Char('\n'), Qt::SkipEmptyParts);

                if (!lines.isEmpty())
                {
                    static const QRegularExpression desktopIdExpression(
                        QStringLiteral(R"(([A-Za-z0-9][A-Za-z0-9._+@-]*\.desktop))"));
                    const QRegularExpressionMatch match
                        = desktopIdExpression.match(lines.constFirst());
                    if (match.hasMatch())
                        return match.captured(1);
                }
            }
        }
#endif
        return fallbackNxmHandlerDesktopId();
    }

    QString desktopEntryDisplayName(const QString& desktopId)
    {
        if (desktopId.isEmpty())
            return {};
        if (desktopId.compare(nxmDesktopEntryId(), Qt::CaseInsensitive) == 0)
            return QStringLiteral("OpenMW Launcher");

#ifdef Q_OS_LINUX
        QStringList applicationDirectories
            = QStandardPaths::standardLocations(QStandardPaths::ApplicationsLocation);
        const QString userApplications
            = QStandardPaths::writableLocation(QStandardPaths::ApplicationsLocation);
        if (!userApplications.isEmpty() && !applicationDirectories.contains(userApplications))
            applicationDirectories.prepend(userApplications);

        for (const QString& directory : applicationDirectories)
        {
            QFile file(QDir(directory).filePath(desktopId));
            if (!file.open(QIODevice::ReadOnly | QIODevice::Text))
                continue;

            const QStringList lines
                = QString::fromUtf8(file.readAll()).split(QLatin1Char('\n'));
            bool inDesktopEntry = false;
            QString plainName;

            for (QString line : lines)
            {
                line = line.trimmed();
                if (line.startsWith(QLatin1Char('[')) && line.endsWith(QLatin1Char(']')))
                {
                    inDesktopEntry = line.compare(
                        QStringLiteral("[Desktop Entry]"), Qt::CaseInsensitive) == 0;
                    continue;
                }

                if (!inDesktopEntry)
                    continue;

                if (line.startsWith(QStringLiteral("Name=")))
                    plainName = line.mid(5).trimmed();
            }

            if (!plainName.isEmpty())
                return plainName;
        }
#endif

        return desktopId;
    }

    bool desktopEntryExists(const QString& desktopId)
    {
#ifdef Q_OS_LINUX
        if (desktopId.isEmpty())
            return false;

        QStringList applicationDirectories
            = QStandardPaths::standardLocations(QStandardPaths::ApplicationsLocation);
        const QString userApplications
            = QStandardPaths::writableLocation(QStandardPaths::ApplicationsLocation);
        if (!userApplications.isEmpty() && !applicationDirectories.contains(userApplications))
            applicationDirectories.prepend(userApplications);

        for (const QString& directory : applicationDirectories)
        {
            if (QFileInfo::exists(QDir(directory).filePath(desktopId)))
                return true;
        }
#endif
        return false;
    }

    bool writeNxmDesktopEntry(QString& error)
    {
#ifndef Q_OS_LINUX
        error = QStringLiteral("Unsupported platform.");
        return false;
#else
        QString applicationsDirectory
            = QStandardPaths::writableLocation(QStandardPaths::ApplicationsLocation);
        if (applicationsDirectory.isEmpty())
        {
            const QString dataHome
                = QStandardPaths::writableLocation(QStandardPaths::GenericDataLocation);
            applicationsDirectory
                = QDir(dataHome).filePath(QStringLiteral("applications"));
        }

        if (applicationsDirectory.isEmpty()
            || !QDir().mkpath(applicationsDirectory))
        {
            error = applicationsDirectory;
            return false;
        }

        const QString desktopPath
            = QDir(applicationsDirectory).filePath(nxmDesktopEntryId());

        QSaveFile file(desktopPath);
        if (!file.open(QIODevice::WriteOnly | QIODevice::Text))
        {
            error = desktopPath;
            return false;
        }

        const QString desktopEntry = QStringLiteral(
            "[Desktop Entry]\n"
            "Type=Application\n"
            "Name=OpenMW Launcher NXM Handler\n"
            "Exec=%1\n"
            "Terminal=false\n"
            "NoDisplay=true\n"
            "MimeType=x-scheme-handler/nxm;\n")
                                         .arg(desktopExecValue(nxmHandlerExecutablePath()));

        const QByteArray data = desktopEntry.toUtf8();
        if (file.write(data) != data.size() || !file.commit())
        {
            error = desktopPath;
            return false;
        }

        return true;
#endif
    }

    bool writeMimeappsDefault(const QString& desktopId, QString& error)
    {
#ifndef Q_OS_LINUX
        error = QStringLiteral("Unsupported platform.");
        return false;
#else
        QString configHome = QString::fromLocal8Bit(qgetenv("XDG_CONFIG_HOME")).trimmed();
        if (configHome.isEmpty())
            configHome = QStandardPaths::writableLocation(QStandardPaths::ConfigLocation);

        if (configHome.isEmpty() || !QDir().mkpath(configHome))
        {
            error = configHome;
            return false;
        }

        const QString mimeappsPath
            = QDir(configHome).filePath(QStringLiteral("mimeapps.list"));

        QStringList lines;
        QFile existing(mimeappsPath);
        if (existing.open(QIODevice::ReadOnly | QIODevice::Text))
            lines = QString::fromUtf8(existing.readAll()).split(
                QLatin1Char('\n'), Qt::KeepEmptyParts);

        const QString section = QStringLiteral("[Default Applications]");
        const QString association = QStringLiteral(
            "x-scheme-handler/nxm=%1;").arg(desktopId);

        bool inDefaults = false;
        bool foundSection = false;
        bool wroteAssociation = false;
        QStringList output;

        for (const QString& originalLine : lines)
        {
            const QString trimmed = originalLine.trimmed();

            if (trimmed.startsWith(QLatin1Char('['))
                && trimmed.endsWith(QLatin1Char(']')))
            {
                if (inDefaults && !wroteAssociation)
                {
                    output << association;
                    wroteAssociation = true;
                }

                inDefaults = trimmed.compare(section, Qt::CaseInsensitive) == 0;
                if (inDefaults)
                    foundSection = true;

                output << originalLine;
                continue;
            }

            if (inDefaults)
            {
                const int equals = trimmed.indexOf(QLatin1Char('='));
                if (equals > 0
                    && trimmed.left(equals).trimmed().compare(
                           QStringLiteral("x-scheme-handler/nxm"),
                           Qt::CaseInsensitive) == 0)
                {
                    if (!wroteAssociation)
                    {
                        output << association;
                        wroteAssociation = true;
                    }
                    continue;
                }
            }

            output << originalLine;
        }

        if (!foundSection)
        {
            if (!output.isEmpty() && !output.constLast().isEmpty())
                output << QString();
            output << section << association;
            wroteAssociation = true;
        }
        else if (inDefaults && !wroteAssociation)
        {
            output << association;
            wroteAssociation = true;
        }

        QSaveFile file(mimeappsPath);
        if (!file.open(QIODevice::WriteOnly | QIODevice::Text))
        {
            error = mimeappsPath;
            return false;
        }

        const QByteArray data = output.join(QLatin1Char('\n')).toUtf8();
        if (file.write(data) != data.size() || !file.commit())
        {
            error = mimeappsPath;
            return false;
        }

        return true;
#endif
    }

    void refreshDesktopDatabase()
    {
#ifdef Q_OS_LINUX
        const QString applicationsDirectory
            = QStandardPaths::writableLocation(QStandardPaths::ApplicationsLocation);

        const QString updateDesktopDatabase
            = QStandardPaths::findExecutable(QStringLiteral("update-desktop-database"));
        if (!updateDesktopDatabase.isEmpty() && !applicationsDirectory.isEmpty())
        {
            QProcess process;
            process.start(updateDesktopDatabase, { applicationsDirectory });
            process.waitForFinished(3000);
        }

        QString kbuildsycoca
            = QStandardPaths::findExecutable(QStringLiteral("kbuildsycoca6"));
        if (kbuildsycoca.isEmpty())
            kbuildsycoca = QStandardPaths::findExecutable(QStringLiteral("kbuildsycoca5"));
        if (!kbuildsycoca.isEmpty())
            QProcess::startDetached(kbuildsycoca, {});
#endif
    }

    bool setDefaultNxmHandler(const QString& desktopId, QString& error)
    {
#ifndef Q_OS_LINUX
        error = QStringLiteral("Unsupported platform.");
        return false;
#else
        if (desktopId.isEmpty())
        {
            error = QStringLiteral("The NXM handler desktop ID is empty.");
            return false;
        }

        bool associationWritten = false;
        const QString gio = QStandardPaths::findExecutable(QStringLiteral("gio"));
        if (!gio.isEmpty())
        {
            QProcess process;
            process.start(gio,
                { QStringLiteral("mime"), QStringLiteral("x-scheme-handler/nxm"),
                    desktopId });
            associationWritten = process.waitForFinished(3000)
                && process.exitStatus() == QProcess::NormalExit
                && process.exitCode() == 0;
        }

        if (!associationWritten)
            associationWritten = writeMimeappsDefault(desktopId, error);

        if (!associationWritten)
            return false;

        refreshDesktopDatabase();

        if (currentNxmHandlerDesktopId().compare(
                desktopId, Qt::CaseInsensitive) != 0)
        {
            error = QStringLiteral("The desktop environment did not accept the new default handler.");
            return false;
        }

        return true;
#endif
    }

    bool setOpenMwAsDefaultNxmHandler(QString& error)
    {
#ifndef Q_OS_LINUX
        error = QStringLiteral("Unsupported platform.");
        return false;
#else
        if (!writeNxmDesktopEntry(error))
            return false;

        refreshDesktopDatabase();
        return setDefaultNxmHandler(nxmDesktopEntryId(), error);
#endif
    }

    void contentSubdirs(const QString& path, QStringList& dirs)
    {
        static const QStringList fileFilter{
            "*.esm",
            "*.esp",
            "*.bsa",
            "*.ba2",
            "*.omwgame",
            "*.omwaddon",
            "*.omwscripts",
        };

        static const QStringList dirFilter{
            "animations",
            "bookart",
            "fonts",
            "icons",
            "interface",
            "l10n",
            "meshes",
            "music",
            "mygui",
            "scripts",
            "shaders",
            "sound",
            "splash",
            "strings",
            "textures",
            "trees",
            "video",
        };

        QDir currentDir(path);
        if (!currentDir.entryInfoList(fileFilter, QDir::Files).empty()
            || !currentDir.entryInfoList(dirFilter, QDir::Dirs | QDir::NoDotAndDotDot).empty())
        {
            dirs.push_back(currentDir.canonicalPath());
            return;
        }

        for (const auto& subdir : currentDir.entryInfoList(QDir::Dirs | QDir::NoDotAndDotDot))
            contentSubdirs(subdir.canonicalFilePath(), dirs);
    }

    QHash<QString, QString> looseAssetFiles(const QString& rootPath)
    {
        static const QStringList assetDirectories{
            QStringLiteral("animations"),
            QStringLiteral("bookart"),
            QStringLiteral("fonts"),
            QStringLiteral("icons"),
            QStringLiteral("interface"),
            QStringLiteral("l10n"),
            QStringLiteral("meshes"),
            QStringLiteral("music"),
            QStringLiteral("mygui"),
            QStringLiteral("scripts"),
            QStringLiteral("shaders"),
            QStringLiteral("sound"),
            QStringLiteral("splash"),
            QStringLiteral("strings"),
            QStringLiteral("textures"),
            QStringLiteral("trees"),
            QStringLiteral("video"),
        };

        QHash<QString, QString> result;
        const QDir root(rootPath);
        if (!root.exists())
            return result;

        const QFileInfoList rootSubdirectories
            = root.entryInfoList(QDir::Dirs | QDir::NoDotAndDotDot | QDir::Readable);

        for (const QFileInfo& subdirectory : rootSubdirectories)
        {
            if (!assetDirectories.contains(subdirectory.fileName(), Qt::CaseInsensitive))
                continue;

            const QString assetRootPath = subdirectory.absoluteFilePath();

            QDirIterator it(assetRootPath, QDir::Files | QDir::NoDotAndDotDot, QDirIterator::Subdirectories);
            while (it.hasNext())
            {
                const QString absolutePath = it.next();
                QString relativePath = root.relativeFilePath(absolutePath);
                relativePath.replace('\\', '/');

                result.insert(relativePath.toLower(), absolutePath);
            }
        }

        return result;
    }

    QSize readDdsSize(const QString& filePath)
    {
        QFile file(filePath);
        if (!file.open(QIODevice::ReadOnly))
            return {};

        const QByteArray header = file.read(20);
        if (header.size() < 20 || header.left(4) != QByteArrayLiteral("DDS "))
            return {};

        const auto readLittleEndian32 = [](const char* data) -> quint32 {
            const auto* bytes = reinterpret_cast<const unsigned char*>(data);
            return static_cast<quint32>(bytes[0])
                | (static_cast<quint32>(bytes[1]) << 8)
                | (static_cast<quint32>(bytes[2]) << 16)
                | (static_cast<quint32>(bytes[3]) << 24);
        };

        const quint32 headerSize = readLittleEndian32(header.constData() + 4);
        const quint32 height = readLittleEndian32(header.constData() + 12);
        const quint32 width = readLittleEndian32(header.constData() + 16);

        if (headerSize != 124 || width == 0 || height == 0
            || width > static_cast<quint32>(std::numeric_limits<int>::max())
            || height > static_cast<quint32>(std::numeric_limits<int>::max()))
            return {};

        return QSize(static_cast<int>(width), static_cast<int>(height));
    }

    QSize readTgaSize(const QString& filePath)
    {
        QFile file(filePath);
        if (!file.open(QIODevice::ReadOnly))
            return {};

        // TGA header stores width and height as little-endian 16-bit values
        // at offsets 12 and 14. No image decoding is needed.
        const QByteArray header = file.read(18);
        if (header.size() < 18)
            return {};

        const auto readLittleEndian16 = [](const char* data) -> quint16 {
            const auto* bytes = reinterpret_cast<const unsigned char*>(data);
            return static_cast<quint16>(bytes[0])
                | (static_cast<quint16>(bytes[1]) << 8);
        };

        const quint16 width = readLittleEndian16(header.constData() + 12);
        const quint16 height = readLittleEndian16(header.constData() + 14);

        if (width == 0 || height == 0)
            return {};

        return QSize(static_cast<int>(width), static_cast<int>(height));
    }

    QSize readTextureSize(const QString& filePath)
    {
        const QString suffix = QFileInfo(filePath).suffix().toLower();

        if (suffix == QLatin1String("dds"))
            return readDdsSize(filePath);

        if (suffix == QLatin1String("tga"))
            return readTgaSize(filePath);

        // QImageReader::size() reads image metadata only; it does not decode
        // the full image. These formats are useful for OpenMW texture mods
        // that do not use DDS.
        if (suffix == QLatin1String("png")
            || suffix == QLatin1String("jpg")
            || suffix == QLatin1String("jpeg")
            || suffix == QLatin1String("bmp"))
        {
            QImageReader reader(filePath);
            reader.setAutoTransform(false);
            return reader.size();
        }

        return {};
    }

    QString textureSizeText(const QSize& size)
    {
        if (!size.isValid() || size.isEmpty())
            return {};

        return QStringLiteral("%1×%2").arg(size.width()).arg(size.height());
    }

    QString normalizedAbsolutePath(const QString& path)
    {
        return QDir::cleanPath(QFileInfo(path).absoluteFilePath());
    }

    bool samePath(const QString& lhs, const QString& rhs)
    {
#ifdef Q_OS_WINDOWS
        constexpr auto caseSensitivity = Qt::CaseInsensitive;
#else
        constexpr auto caseSensitivity = Qt::CaseSensitive;
#endif
        return normalizedAbsolutePath(lhs).compare(normalizedAbsolutePath(rhs), caseSensitivity) == 0;
    }

    bool isDirectChildPath(const QString& childPath, const QString& rootPath)
    {
        if (rootPath.isEmpty())
            return false;

        const QFileInfo childInfo(normalizedAbsolutePath(childPath));
        return samePath(childInfo.absolutePath(), normalizedAbsolutePath(rootPath));
    }

    QList<QPair<int, QListWidgetItem*>> sortedSelectedItems(QListWidget* list, bool reverse = false)
    {
        QList<QPair<int, QListWidgetItem*>> sortedItems;
        for (QListWidgetItem* item : list->selectedItems())
            sortedItems.append(qMakePair(list->row(item), item));

        if (reverse)
            std::sort(sortedItems.begin(), sortedItems.end(), [](auto a, auto b) { return a.first > b.first; });
        else
            std::sort(sortedItems.begin(), sortedItems.end(), [](auto a, auto b) { return a.first < b.first; });

        return sortedItems;
    }
}

namespace Launcher
{
    namespace
    {
        struct HandleNavMeshToolMessage
        {
            int mCellsCount;
            int mExpectedMaxProgress;
            int mMaxProgress;
            int mProgress;

            HandleNavMeshToolMessage operator()(NavMeshTool::ExpectedCells&& message) const
            {
                return HandleNavMeshToolMessage{ static_cast<int>(message.mCount), mExpectedMaxProgress,
                    static_cast<int>(message.mCount) * 100, mProgress };
            }

            HandleNavMeshToolMessage operator()(NavMeshTool::ProcessedCells&& message) const
            {
                return HandleNavMeshToolMessage{ mCellsCount, mExpectedMaxProgress, mMaxProgress,
                    std::max(mProgress, static_cast<int>(message.mCount)) };
            }

            HandleNavMeshToolMessage operator()(NavMeshTool::ExpectedTiles&& message) const
            {
                const int expectedMaxProgress = mCellsCount + static_cast<int>(message.mCount);
                return HandleNavMeshToolMessage{ mCellsCount, expectedMaxProgress,
                    std::max(mMaxProgress, expectedMaxProgress), mProgress };
            }

            HandleNavMeshToolMessage operator()(NavMeshTool::GeneratedTiles&& message) const
            {
                int progress = mCellsCount + static_cast<int>(message.mCount);
                if (mExpectedMaxProgress < mMaxProgress)
                    progress += static_cast<int>(std::round((mMaxProgress - mExpectedMaxProgress)
                        * (static_cast<float>(progress) / static_cast<float>(mExpectedMaxProgress))));
                return HandleNavMeshToolMessage{ mCellsCount, mExpectedMaxProgress, mMaxProgress,
                    std::max(mProgress, progress) };
            }
        };

        int getMaxNavMeshDbFileSizeMiB()
        {
            return static_cast<int>(Settings::navigator().mMaxNavmeshdbFileSize / (1024 * 1024));
        }
    }
}

Launcher::DataFilesPage::DataFilesPage(const Files::ConfigurationManager& cfg, Config::GameSettings& gameSettings,
    Config::LauncherSettings& launcherSettings, MainDialog* parent)
    : QWidget(parent)
    , mDirectoryPickerDialog(new QDialog(this))
    , mMainDialog(parent)
    , mCfgMgr(cfg)
    , mGameSettings(gameSettings)
    , mLauncherSettings(launcherSettings)
    , mNavMeshToolInvoker(new Process::ProcessInvoker(this))
    , mReloadCellsThread(&DataFilesPage::reloadCells, this)
{
    ui.setupUi(this);
    mDirectoryPicker.setupUi(mDirectoryPickerDialog);
    setObjectName("DataFilesPage");
    mSelector = new ContentSelectorView::ContentSelector(ui.contentSelectorWidget, /*showOMWScripts=*/true);
    const QString encoding = mGameSettings.value("encoding", { "win1252" }).value;
    mSelector->setEncoding(encoding);

    QVector<std::pair<QString, QString>> languages = { { "English", tr("English") }, { "French", tr("French") },
        { "German", tr("German") }, { "Italian", tr("Italian") }, { "Polish", tr("Polish") },
        { "Russian", tr("Russian") }, { "Spanish", tr("Spanish") } };

    for (auto lang : languages)
    {
        mSelector->languageBox()->addItem(lang.second, lang.first);
    }

    mNewProfileDialog = new TextInputDialog(tr("New Content List"), tr("Content List name:"), this);
    mCloneProfileDialog = new TextInputDialog(tr("Clone Content List"), tr("Content List name:"), this);

    connect(mNewProfileDialog->lineEdit(), &LineEdit::textChanged, this, &DataFilesPage::updateNewProfileOkButton);
    connect(mCloneProfileDialog->lineEdit(), &LineEdit::textChanged, this, &DataFilesPage::updateCloneProfileOkButton);
    connect(ui.directoryAddSubdirsButton, &QPushButton::released, this, [this]() { this->addSubdirectories(true); });
    connect(ui.directoryInsertButton, &QPushButton::released, this, [this]() { this->addSubdirectories(false); });
    connect(ui.directoryUpButton, &QPushButton::released, this,
        [this]() { this->moveSources(ui.directoryListWidget, -1); });
    connect(ui.directoryDownButton, &QPushButton::released, this,
        [this]() { this->moveSources(ui.directoryListWidget, 1); });
    connect(ui.directoryRemoveButton, &QPushButton::released, this, &DataFilesPage::removeDirectory);
    connect(ui.modsDirectoryBrowseButton, &QPushButton::released, this, [this]() { chooseModsDirectory(); });
    connect(ui.modsDirectoryClearButton, &QPushButton::released, this, [this]() { clearModsDirectory(); });

    auto* installArchiveButton = new QPushButton(tr("Install from Archive..."), this);
    installArchiveButton->setToolTip(
        tr("Select a ZIP, 7Z or RAR mod archive and analyze its installation structure."));
    ui.modsDirectoryLayout->insertWidget(3, installArchiveButton);
    connect(installArchiveButton, &QPushButton::released, this, &DataFilesPage::analyzeModArchive);

    auto* nexusModsButton = new QPushButton(tr("Nexus Mods..."), this);
    nexusModsButton->setToolTip(
        tr("Connect to Nexus Mods with a Personal API key for development and testing."));
    ui.modsDirectoryLayout->insertWidget(4, nexusModsButton);
    connect(nexusModsButton, &QPushButton::released, this, &DataFilesPage::connectNexusMods);

#ifdef Q_OS_LINUX
    auto* nxmHandlerButton = new QPushButton(tr("NXM Handler..."), this);
    nxmHandlerButton->setToolTip(
        tr("View or change the default application for Nexus Mods Mod Manager Download links."));
    ui.modsDirectoryLayout->insertWidget(5, nxmHandlerButton);
    connect(nxmHandlerButton, &QPushButton::released, this, &DataFilesPage::showNxmHandlerSettings);
#endif

    ui.modsDirectoryLineEdit->setText(mLauncherSettings.getModsDirectory());

    connect(
        ui.archiveUpButton, &QPushButton::released, this, [this]() { this->moveSources(ui.archiveListWidget, -1); });
    connect(
        ui.archiveDownButton, &QPushButton::released, this, [this]() { this->moveSources(ui.archiveListWidget, 1); });
    connect(ui.directoryListWidget->model(), &QAbstractItemModel::rowsMoved, this, &DataFilesPage::sortDirectories);
    connect(ui.archiveListWidget->model(), &QAbstractItemModel::rowsMoved, this, &DataFilesPage::sortArchives);

    buildView();
    loadSettings();

    // Connect signal and slot after the settings have been loaded. We only care about the user changing
    // the addons and don't want to get signals of the system doing it during startup.
    connect(mSelector, &ContentSelectorView::ContentSelector::signalAddonDataChanged, this,
        &DataFilesPage::slotAddonDataChanged);

    // Groundcover assignment is a launcher configuration action, not merely
    // a pending UI edit. Persist it immediately so groundcover= in openmw.cfg
    // and [Groundcover] enabled=true in settings.cfg are visible at once,
    // without closing/restarting the launcher.
    connect(mSelector, &ContentSelectorView::ContentSelector::signalGroundcoverChanged, this,
        [this](bool enabled) {
            if (enabled)
                mMainDialog->setGroundcoverEnabled(true);
            mMainDialog->writeSettings();
        });

    // Sorting is an explicit user action. Persist the resulting load order
    // immediately instead of waiting for launcher shutdown.
    connect(mSelector, &ContentSelectorView::ContentSelector::signalLoadOrderChanged, this,
        [this]() { mMainDialog->writeSettings(); });

    // The combined Mods / Plugins table shows both plug-in mods and
    // asset-only mods. A drag can therefore change two independent orders:
    // plug-in-to-plug-in order controls content=, while the relative position
    // of their owning directories controls data= asset priority. Mirror the
    // directory order, refresh conflicts and persist both immediately.
    connect(mSelector, &ContentSelectorView::ContentSelector::signalDataDirectoryOrderChanged, this,
        [this](const QStringList& paths) {
            applyDataDirectoryOrder(paths);
            updateAssetConflictStats();
            mMainDialog->writeSettings();
        });

    connect(mSelector, &ContentSelectorView::ContentSelector::signalShowAssetConflicts, this,
        [this](const QString& path) { showAssetConflictDetails(path); });

    connect(mSelector, &ContentSelectorView::ContentSelector::signalShowNexusModRequested, this,
        [this](const QString& path) { showNexusModPage(path); });

    connect(mSelector, &ContentSelectorView::ContentSelector::signalDeleteModRequested, this,
        [this](const QString& path) { deleteManagedMod(path); });

    mReloadCellsTimer = new QTimer(this);
    mReloadCellsTimer->setSingleShot(true);
    mReloadCellsTimer->setInterval(200);
    connect(mReloadCellsTimer, &QTimer::timeout, this, &DataFilesPage::onReloadCellsTimerTimeout);

    // Call manually to indicate all changes to addon data during startup.
    onReloadCellsTimerTimeout();
}

Launcher::DataFilesPage::~DataFilesPage()
{
    {
        const std::lock_guard lock(mReloadCellsMutex);
        mAbortReloadCells = true;
        mStartReloadCells.notify_one();
    }
    mReloadCellsThread.join();
}

void Launcher::DataFilesPage::buildView()
{
    QToolButton* refreshButton = mSelector->refreshButton();

    // tool buttons
    ui.newProfileButton->setToolTip("Create a new Content List");
    ui.cloneProfileButton->setToolTip("Clone the current Content List");
    ui.deleteProfileButton->setToolTip("Delete an existing Content List");

    // combo box
    ui.profilesComboBox->addItem(mDefaultContentListName);
    ui.profilesComboBox->setPlaceholderText(QString("Select a Content List..."));
    ui.profilesComboBox->setCurrentIndex(ui.profilesComboBox->findText(QLatin1String(mDefaultContentListName)));

    // Add the actions to the toolbuttons
    ui.newProfileButton->setDefaultAction(ui.newProfileAction);
    ui.cloneProfileButton->setDefaultAction(ui.cloneProfileAction);
    ui.deleteProfileButton->setDefaultAction(ui.deleteProfileAction);
    refreshButton->setDefaultAction(ui.refreshDataFilesAction);

    // establish connections
    connect(ui.profilesComboBox, qOverload<int>(&::ProfilesComboBox::currentIndexChanged), this,
        &DataFilesPage::slotProfileChanged);

    connect(ui.profilesComboBox, &::ProfilesComboBox::profileRenamed, this, &DataFilesPage::slotProfileRenamed);

    connect(ui.profilesComboBox, qOverload<const QString&, const QString&>(&::ProfilesComboBox::signalProfileChanged),
        this, &DataFilesPage::slotProfileChangedByUser);

    connect(ui.refreshDataFilesAction, &QAction::triggered, this, &DataFilesPage::slotRefreshButtonClicked);

    connect(ui.updateNavMeshButton, &QPushButton::clicked, this, &DataFilesPage::startNavMeshTool);
    connect(ui.cancelNavMeshButton, &QPushButton::clicked, this, &DataFilesPage::killNavMeshTool);

    connect(mNavMeshToolInvoker->getProcess(), &QProcess::readyReadStandardOutput, this,
        &DataFilesPage::readNavMeshToolStdout);
    connect(mNavMeshToolInvoker->getProcess(), &QProcess::readyReadStandardError, this,
        &DataFilesPage::readNavMeshToolStderr);
    connect(mNavMeshToolInvoker->getProcess(), qOverload<int, QProcess::ExitStatus>(&QProcess::finished), this,
        &DataFilesPage::navMeshToolFinished);

    buildArchiveContextMenu();
    buildDataFilesContextMenu();
    buildDirectoryPickerContextMenu();
}

void Launcher::DataFilesPage::slotCopySelectedItemsPaths()
{
    QClipboard* clipboard = QApplication::clipboard();
    QStringList filepaths;

    for (QListWidgetItem* item : ui.directoryListWidget->selectedItems())
    {
        QString path = qvariant_cast<Config::SettingValue>(item->data(Qt::UserRole)).originalRepresentation;
        filepaths.push_back(path);
    }

    if (!filepaths.isEmpty())
    {
        clipboard->setText(filepaths.join("\n"));
    }
}

void Launcher::DataFilesPage::slotOpenSelectedItemsPaths()
{
    QListWidgetItem* item = ui.directoryListWidget->currentItem();
    QUrl confFolderUrl = QUrl::fromLocalFile(qvariant_cast<Config::SettingValue>(item->data(Qt::UserRole)).value);
    QDesktopServices::openUrl(confFolderUrl);
}

void Launcher::DataFilesPage::buildArchiveContextMenu()
{
    connect(ui.archiveListWidget, &QListWidget::customContextMenuRequested, this,
        &DataFilesPage::slotShowArchiveContextMenu);

    mArchiveContextMenu = new QMenu(ui.archiveListWidget);
    mArchiveContextMenu->addAction(tr("&Check Selected"), this,
        [this]() { setCheckStateForMultiSelectedItems(ui.archiveListWidget, Qt::Checked); });
    mArchiveContextMenu->addAction(tr("&Uncheck Selected"), this,
        [this]() { setCheckStateForMultiSelectedItems(ui.archiveListWidget, Qt::Unchecked); });
}

void Launcher::DataFilesPage::buildDataFilesContextMenu()
{
    connect(ui.directoryListWidget, &QListWidget::customContextMenuRequested, this,
        &DataFilesPage::slotShowDataFilesContextMenu);

    mDataFilesContextMenu = new QMenu(ui.directoryListWidget);
    mDataFilesContextMenu->addAction(
        tr("&Copy Path(s) to Clipboard"), this, &Launcher::DataFilesPage::slotCopySelectedItemsPaths);
    mDataFilesContextMenu->addAction(
        tr("&Open Path in File Explorer"), this, &Launcher::DataFilesPage::slotOpenSelectedItemsPaths);
}

void Launcher::DataFilesPage::buildDirectoryPickerContextMenu()
{
    connect(mDirectoryPicker.dirListWidget, &QListWidget::customContextMenuRequested, this,
        &DataFilesPage::slotShowDirectoryPickerContextMenu);

    mDirectoryPickerMenu = new QMenu(mDirectoryPicker.dirListWidget);
    mDirectoryPickerMenu->addAction(tr("&Check Selected"), this,
        [this]() { setCheckStateForMultiSelectedItems(mDirectoryPicker.dirListWidget, Qt::Checked); });
    mDirectoryPickerMenu->addAction(tr("&Uncheck Selected"), this,
        [this]() { setCheckStateForMultiSelectedItems(mDirectoryPicker.dirListWidget, Qt::Unchecked); });
}

QStringList Launcher::DataFilesPage::modsDirectoryChildren() const
{
    QStringList result;

    const QString rootPath = mLauncherSettings.getModsDirectory();
    if (rootPath.isEmpty())
        return result;

    const QDir root(rootPath);
    if (!root.exists())
        return result;

    const QFileInfoList entries = root.entryInfoList(
        QDir::Dirs | QDir::NoDotAndDotDot | QDir::Readable, QDir::Name | QDir::IgnoreCase);

    for (const QFileInfo& entry : entries)
    {
        QString path = entry.canonicalFilePath();
        if (path.isEmpty())
            path = entry.absoluteFilePath();
        result.push_back(QDir::cleanPath(path));
    }

    return result;
}

void Launcher::DataFilesPage::removeManagedModsDirectoryEntries(const QString& rootPath)
{
    if (rootPath.isEmpty())
        return;

    for (int row = ui.directoryListWidget->count() - 1; row >= 0; --row)
    {
        QListWidgetItem* item = ui.directoryListWidget->item(row);
        if (!item || !(item->flags() & Qt::ItemIsEnabled))
            continue;

        const Config::SettingValue setting = qvariant_cast<Config::SettingValue>(item->data(Qt::UserRole));
        if (isDirectChildPath(setting.value, rootPath))
            delete ui.directoryListWidget->takeItem(row);
    }
}

void Launcher::DataFilesPage::analyzeModArchive()
{
    const QString modsDirectory = mLauncherSettings.getModsDirectory();
    if (modsDirectory.isEmpty() || !QDir(modsDirectory).exists())
    {
        QMessageBox::warning(this, tr("Install Mod"),
            tr("Select a valid Mods Directory before installing a mod from an archive."));
        return;
    }

    const QString archivePath = QFileDialog::getOpenFileName(this, tr("Select Mod Archive"), QString(),
        tr("Mod Archives (*.zip *.7z *.rar);;All Files (*)"));

    if (archivePath.isEmpty())
        return;

    installModArchive(archivePath);
}

void Launcher::DataFilesPage::installModArchive(const QString& archivePath, const QString& suggestedModName,
    const QString& archiveDisplayName, const NexusModMetadata* nexusMetadata,
    const QString& overlayTargetPath, QString* installedPathOut)
{
    if (installedPathOut)
        installedPathOut->clear();

    const QString modsDirectory = mLauncherSettings.getModsDirectory();
    if (modsDirectory.isEmpty() || !QDir(modsDirectory).exists())
    {
        QMessageBox::warning(this, tr("Install Mod"),
            tr("Select a valid Mods Directory before installing a mod from an archive."));
        return;
    }

    if (archivePath.isEmpty() || !QFileInfo::exists(archivePath))
    {
        QMessageBox::critical(this, tr("Install Mod"), tr("The downloaded archive does not exist."));
        return;
    }

    const bool overlayInstall = !overlayTargetPath.trimmed().isEmpty();
    QString normalizedOverlayTargetPath;

    if (overlayInstall)
    {
        normalizedOverlayTargetPath = normalizedAbsolutePath(overlayTargetPath);
        const QString normalizedModsRoot = normalizedAbsolutePath(modsDirectory);
        const QFileInfo targetInfo(normalizedOverlayTargetPath);

        if (!isDirectChildPath(normalizedOverlayTargetPath, normalizedModsRoot)
            || !targetInfo.exists() || !targetInfo.isDir() || targetInfo.isSymLink())
        {
            QMessageBox::critical(this, tr("Translation Overlay"),
                tr("The selected base mod directory is not a safe managed mod target."));
            return;
        }

        const QString metadataPath
            = QDir(normalizedOverlayTargetPath).filePath(QStringLiteral("openmw-meta.ini"));
        if (!QFileInfo(metadataPath).isFile())
        {
            QMessageBox::critical(this, tr("Translation Overlay"),
                tr("Translation overlays require a base mod installed and managed by this launcher."));
            return;
        }
    }

    const QString displayArchiveName
        = archiveDisplayName.isEmpty() ? QFileInfo(archivePath).fileName() : archiveDisplayName;
    const QString initialModName = overlayInstall
        ? QFileInfo(normalizedOverlayTargetPath).fileName()
        : (suggestedModName.isEmpty() ? QFileInfo(archivePath).completeBaseName() : suggestedModName);

    QString sevenZipExecutable;

    const auto findSevenZipExecutable = [&sevenZipExecutable]() -> QString {
        if (!sevenZipExecutable.isEmpty())
            return sevenZipExecutable;

        static const QStringList candidates{
            QStringLiteral("7zz"),
            QStringLiteral("7z"),
            QStringLiteral("7za"),
        };

        for (const QString& candidate : candidates)
        {
            const QString executable = QStandardPaths::findExecutable(candidate);
            if (!executable.isEmpty())
            {
                sevenZipExecutable = executable;
                break;
            }
        }

        return sevenZipExecutable;
    };

    const auto listArchiveWithSevenZip
        = [this, &archivePath, &findSevenZipExecutable](
              QStringList& listedPaths, QString& listedFormat,
              QString& fallbackError) -> bool {
            listedPaths.clear();
            listedFormat.clear();
            fallbackError.clear();

            const QString executable = findSevenZipExecutable();
            if (executable.isEmpty())
            {
                fallbackError = tr(
                    "No 7-Zip executable (7zz, 7z or 7za) was found in PATH.");
                return false;
            }

            QProcess process;
            process.setProcessChannelMode(QProcess::SeparateChannels);
            process.start(executable,
                { QStringLiteral("l"), QStringLiteral("-slt"),
                    QStringLiteral("-sccUTF-8"), archivePath });

            if (!process.waitForStarted(5000))
            {
                fallbackError = process.errorString();
                return false;
            }

            process.closeWriteChannel();
            process.waitForFinished(-1);

            const QString standardOutput
                = QString::fromUtf8(process.readAllStandardOutput());
            const QString standardError
                = QString::fromUtf8(process.readAllStandardError()).trimmed();

            if (process.exitStatus() != QProcess::NormalExit
                || process.exitCode() != 0)
            {
                fallbackError = standardError;
                if (fallbackError.isEmpty())
                    fallbackError = standardOutput.trimmed();
                if (fallbackError.isEmpty())
                    fallbackError = process.errorString();
                return false;
            }

            QString currentPath;
            QString currentFolder;
            bool hasFolderField = false;

            const auto flushRecord
                = [&listedPaths, &currentPath, &currentFolder,
                      &hasFolderField]() {
                    if (!currentPath.isEmpty()
                        && hasFolderField
                        && currentFolder == QLatin1String("-"))
                    {
                        QString path = currentPath.trimmed();
                        path.replace('\\', '/');

                        while (path.startsWith(QLatin1String("./")))
                            path.remove(0, 2);
                        while (path.startsWith('/'))
                            path.remove(0, 1);

                        if (!path.isEmpty())
                            listedPaths.push_back(path);
                    }

                    currentPath.clear();
                    currentFolder.clear();
                    hasFolderField = false;
                };

            const QStringList lines
                = standardOutput.split(QLatin1Char('\n'), Qt::KeepEmptyParts);

            for (QString line : lines)
            {
                if (line.endsWith(QLatin1Char('\r')))
                    line.chop(1);

                if (line.isEmpty())
                {
                    flushRecord();
                    continue;
                }

                if (line.startsWith(QLatin1String("Path = ")))
                {
                    if (!currentPath.isEmpty())
                        flushRecord();

                    currentPath = line.mid(7);
                    continue;
                }

                if (line.startsWith(QLatin1String("Folder = ")))
                {
                    currentFolder = line.mid(9).trimmed();
                    hasFolderField = true;
                    continue;
                }

                if (listedFormat.isEmpty()
                    && line.startsWith(QLatin1String("Type = ")))
                {
                    listedFormat = line.mid(7).trimmed();
                }
            }

            flushRecord();
            listedPaths.removeDuplicates();

            if (listedPaths.isEmpty())
            {
                fallbackError = standardOutput.trimmed();
                if (fallbackError.isEmpty())
                    fallbackError = standardError;
                return false;
            }

            if (listedFormat.isEmpty())
                listedFormat = QStringLiteral("7-Zip");
            else
                listedFormat += QStringLiteral(" (7-Zip)");

            return true;
        };

    QStringList filePaths;
    QString archiveFormat;
    QString archiveError;
    bool use7ZipFallback = false;

    const QByteArray encodedPath = QFile::encodeName(archivePath);

    struct archive* archiveHandle = archive_read_new();
    if (!archiveHandle)
    {
        archiveError = tr("Could not initialize the archive reader.");
    }
    else
    {
        archive_read_support_filter_all(archiveHandle);
        archive_read_support_format_all(archiveHandle);

        if (archive_read_open_filename(
                archiveHandle, encodedPath.constData(), 10240) != ARCHIVE_OK)
        {
            const char* error = archive_error_string(archiveHandle);
            archiveError
                = error ? QString::fromUtf8(error) : tr("Unknown error");
        }
        else
        {
            struct archive_entry* entry = nullptr;
            int readResult = ARCHIVE_OK;

            while ((readResult
                       = archive_read_next_header(archiveHandle, &entry))
                == ARCHIVE_OK)
            {
                if (archiveFormat.isEmpty())
                {
                    const char* formatName = archive_format_name(archiveHandle);
                    if (formatName)
                        archiveFormat = QString::fromUtf8(formatName);
                }

                if (archive_entry_filetype(entry) == AE_IFDIR)
                {
                    archive_read_data_skip(archiveHandle);
                    continue;
                }

                const char* rawPath = archive_entry_pathname_utf8(entry);
                if (!rawPath)
                    rawPath = archive_entry_pathname(entry);
                if (!rawPath)
                {
                    archive_read_data_skip(archiveHandle);
                    continue;
                }

                QString path = QString::fromUtf8(rawPath).trimmed();
                path.replace('\\', '/');

                while (path.startsWith(QLatin1String("./")))
                    path.remove(0, 2);
                while (path.startsWith('/'))
                    path.remove(0, 1);

                if (!path.isEmpty())
                    filePaths.push_back(path);

                archive_read_data_skip(archiveHandle);
            }

            if (readResult != ARCHIVE_EOF)
            {
                const char* error = archive_error_string(archiveHandle);
                archiveError
                    = error ? QString::fromUtf8(error) : tr("Unknown error");
            }
        }

        archive_read_free(archiveHandle);
    }

    if (!archiveError.isEmpty())
    {
        QStringList fallbackPaths;
        QString fallbackFormat;
        QString fallbackError;

        if (listArchiveWithSevenZip(
                fallbackPaths, fallbackFormat, fallbackError))
        {
            filePaths = fallbackPaths;
            archiveFormat = fallbackFormat;
            archiveError.clear();
            use7ZipFallback = true;
        }
        else
        {
            archiveError += QStringLiteral("\n\n")
                + tr("7-Zip fallback failed:\n%1").arg(fallbackError);
        }
    }

    if (!archiveError.isEmpty())
    {
        QMessageBox::warning(this, tr("Archive Analysis"),
            tr("The archive was only partially read:\n%1").arg(archiveError));
    }

    // Archive layout detection follows the same general rule used by
    // BAIN-style managers: first decide whether the current level is already a
    // valid/simple Morrowind data root. Only when it is not, inspect its DIRECT
    // child directories for wrapped roots or parallel subpackages.
    //
    // Never search asset directory names recursively. A normal mod may contain
    // paths such as mwse/config/foo/animations; that does not make
    // mwse/config/foo a separate package.
    static const QStringList assetDirectories{
        QStringLiteral("animations"),
        QStringLiteral("bookart"),
        QStringLiteral("distantland"),
        QStringLiteral("distantlod"),
        QStringLiteral("fonts"),
        QStringLiteral("icons"),
        QStringLiteral("interface"),
        QStringLiteral("iwy"),
        QStringLiteral("kw"),
        QStringLiteral("l10n"),
        QStringLiteral("localization"),
        QStringLiteral("meshes"),
        QStringLiteral("music"),
        QStringLiteral("mwse"),
        QStringLiteral("mygui"),
        QStringLiteral("scripts"),
        QStringLiteral("shaders"),
        QStringLiteral("sound"),
        QStringLiteral("splash"),
        QStringLiteral("strings"),
        QStringLiteral("textures"),
        QStringLiteral("trees"),
        QStringLiteral("video"),
    };

    static const QStringList rootFileExtensions{
        QStringLiteral("esm"),
        QStringLiteral("esp"),
        QStringLiteral("bsa"),
        QStringLiteral("ba2"),
        QStringLiteral("ini"),
        QStringLiteral("omwgame"),
        QStringLiteral("omwaddon"),
        QStringLiteral("omwscripts"),
    };

    const auto joinArchiveRoot = [](const QString& parent, const QString& child) {
        return parent.isEmpty() ? child : parent + '/' + child;
    };

    const auto relativePathFromRoot = [](const QString& path, const QString& root) {
        if (root.isEmpty())
            return path;

        const QString prefix = root + '/';
        if (!path.startsWith(prefix, Qt::CaseInsensitive))
            return QString();

        return path.mid(prefix.size());
    };

    const auto directChildDirectories
        = [&filePaths, &relativePathFromRoot](const QString& root) {
            QSet<QString> childSet;

            for (const QString& path : filePaths)
            {
                const QString relativePath = relativePathFromRoot(path, root);
                if (relativePath.isEmpty())
                    continue;

                const QStringList parts
                    = relativePath.split('/', Qt::SkipEmptyParts);
                if (parts.size() >= 2)
                    childSet.insert(parts.constFirst());
            }

            QStringList children = childSet.values();
            std::sort(children.begin(), children.end(),
                [](const QString& lhs, const QString& rhs) {
                    return lhs.compare(rhs, Qt::CaseInsensitive) < 0;
                });
            return children;
        };

    const auto isRecognizableDataRoot
        = [&filePaths, &relativePathFromRoot](const QString& root) {
            for (const QString& path : filePaths)
            {
                const QString relativePath = relativePathFromRoot(path, root);
                if (relativePath.isEmpty())
                    continue;

                const QStringList parts
                    = relativePath.split('/', Qt::SkipEmptyParts);
                if (parts.isEmpty())
                    continue;

                // A recognised asset directory must be an IMMEDIATE child of
                // this candidate root.
                if (parts.size() >= 2
                    && assetDirectories.contains(
                        parts.constFirst(), Qt::CaseInsensitive))
                {
                    return true;
                }

                // Plugins/configs count only when they are loose files directly
                // in the candidate root.
                if (parts.size() == 1)
                {
                    const QString extension
                        = QFileInfo(parts.constFirst()).suffix().toLower();
                    if (rootFileExtensions.contains(extension))
                        return true;
                }
            }

            return false;
        };

    const auto resolveDirectPackageRoot
        = [&directChildDirectories, &isRecognizableDataRoot,
              &joinArchiveRoot](const QString& candidateRoot) {
            if (isRecognizableDataRoot(candidateRoot))
                return candidateRoot;

            // "Data Files" is a conventional transparent wrapper for Morrowind.
            const QStringList childDirectories
                = directChildDirectories(candidateRoot);
            if (childDirectories.size() == 1
                && childDirectories.constFirst().compare(
                       QStringLiteral("Data Files"), Qt::CaseInsensitive) == 0)
            {
                const QString dataFilesRoot
                    = joinArchiveRoot(
                        candidateRoot, childDirectories.constFirst());
                if (isRecognizableDataRoot(dataFilesRoot))
                    return dataFilesRoot;
            }

            return QString();
        };

    QStringList roots;
    QString layoutType;

    // Peel neutral single-folder wrappers only while the current level itself
    // is not already a valid data root. Twenty levels is intentionally far
    // beyond any sane archive layout while still bounding malformed input.
    QString scanRoot;
    for (int depth = 0; depth < 20; ++depth)
    {
        if (isRecognizableDataRoot(scanRoot))
        {
            roots.push_back(scanRoot);
            layoutType = scanRoot.isEmpty()
                ? tr("Simple mod (data files at archive root)")
                : tr("Single wrapped data root");
            break;
        }

        const QStringList children = directChildDirectories(scanRoot);
        QStringList directPackageRoots;

        for (const QString& child : children)
        {
            const QString candidateRoot = joinArchiveRoot(scanRoot, child);
            const QString resolvedRoot
                = resolveDirectPackageRoot(candidateRoot);
            if (!resolvedRoot.isEmpty())
                directPackageRoots.push_back(resolvedRoot);
        }

        if (directPackageRoots.size() >= 2)
        {
            roots = directPackageRoots;
            layoutType = tr("BAIN-like package with multiple subpackages");
            break;
        }

        if (directPackageRoots.size() == 1)
        {
            roots = directPackageRoots;
            layoutType = tr("Single wrapped data root");
            break;
        }

        if (children.size() != 1)
            break;

        scanRoot = joinArchiveRoot(scanRoot, children.constFirst());
    }

    if (roots.isEmpty())
        layoutType = tr("No recognizable Morrowind data root");

    QHash<QString, int> filesPerRoot;
    for (const QString& root : roots)
    {
        int count = 0;
        const QString prefix = root.isEmpty() ? QString() : root + '/';

        for (const QString& path : filePaths)
        {
            if (root.isEmpty()
                || path.startsWith(prefix, Qt::CaseInsensitive))
            {
                ++count;
            }
        }

        filesPerRoot.insert(root, count);
    }

    QDialog dialog(this);
    dialog.setWindowTitle(tr("Archive Analysis — %1").arg(displayArchiveName));
    dialog.resize(850, 520);

    auto* layout = new QVBoxLayout(&dialog);

    auto* summary = new QLabel(
        tr("Archive: %1\nFormat: %2\nFiles: %3\nDetected layout: %4")
            .arg(displayArchiveName)
            .arg(archiveFormat.isEmpty() ? tr("Unknown") : archiveFormat)
            .arg(filePaths.size())
            .arg(layoutType),
        &dialog);
    summary->setTextInteractionFlags(Qt::TextSelectableByMouse);
    layout->addWidget(summary);

    auto* note = new QLabel(
        tr("Select subpackages to preview the final file set. Selected packages are layered from top to bottom; "
           "later rows override earlier rows with the same relative path. Green = package contributes files, "
           "red = all of its files are overridden."),
        &dialog);
    note->setWordWrap(true);
    layout->addWidget(note);

    auto* modNameLayout = new QHBoxLayout;
    auto* modNameLabel = new QLabel(
        overlayInstall ? tr("Target mod:") : tr("Mod name:"), &dialog);
    auto* modNameEdit = new QLineEdit(initialModName, &dialog);
    modNameEdit->setReadOnly(overlayInstall);
    modNameEdit->setToolTip(overlayInstall
        ? tr("Translation files will be layered into this managed mod directory.")
        : tr("The mod will be installed as one subdirectory of the configured Mods Directory."));
    modNameLayout->addWidget(modNameLabel);
    modNameLayout->addWidget(modNameEdit, 1);
    layout->addLayout(modNameLayout);

    QHash<QString, QSet<QString>> filesByRoot;
    for (const QString& root : roots)
    {
        QSet<QString> rootFiles;
        const QString prefix = root.isEmpty() ? QString() : root + '/';

        for (const QString& path : filePaths)
        {
            QString relativePath;
            if (root.isEmpty())
                relativePath = path;
            else if (path.startsWith(prefix, Qt::CaseInsensitive))
                relativePath = path.mid(prefix.size());
            else
                continue;

            // If another detected data root is nested below this one, its files
            // belong to that subpackage rather than to the parent package.
            bool belongsToNestedRoot = false;
            for (const QString& otherRoot : roots)
            {
                if (otherRoot == root || otherRoot.isEmpty())
                    continue;

                const QString nestedPrefix = otherRoot + '/';
                if (path.startsWith(nestedPrefix, Qt::CaseInsensitive)
                    && (root.isEmpty() || otherRoot.startsWith(prefix, Qt::CaseInsensitive)))
                {
                    belongsToNestedRoot = true;
                    break;
                }
            }

            if (belongsToNestedRoot)
                continue;

            relativePath.replace('\\', '/');
            while (relativePath.startsWith(QLatin1String("./")))
                relativePath.remove(0, 2);

            if (!relativePath.isEmpty())
                rootFiles.insert(relativePath.toLower());
        }

        filesByRoot.insert(root, rootFiles);
    }

    auto* table = new QTableWidget(&dialog);
    table->setColumnCount(7);
    table->setHorizontalHeaderLabels(
        { tr("Use"), tr("No."), tr("Detected data root / subpackage"), tr("Files"),
            tr("Active"), tr("Overridden"), tr("Status") });
    table->setEditTriggers(QAbstractItemView::NoEditTriggers);
    table->setSelectionBehavior(QAbstractItemView::SelectRows);
    table->setAlternatingRowColors(true);
    table->verticalHeader()->setVisible(false);

    if (roots.isEmpty())
    {
        table->setRowCount(1);
        auto* item = new QTableWidgetItem(tr("No candidate data roots were detected."));
        table->setSpan(0, 0, 1, 7);
        table->setItem(0, 0, item);
    }
    else
    {
        table->setRowCount(roots.size());

        for (int row = 0; row < roots.size(); ++row)
        {
            const QString& root = roots.at(row);

            auto* useItem = new QTableWidgetItem;
            useItem->setFlags((useItem->flags() | Qt::ItemIsUserCheckable) & ~Qt::ItemIsEditable);
            useItem->setCheckState(Qt::Checked);
            useItem->setTextAlignment(Qt::AlignCenter);
            table->setItem(row, 0, useItem);

            auto* numberItem = new QTableWidgetItem(QString::number(row + 1));
            numberItem->setTextAlignment(Qt::AlignCenter);
            table->setItem(row, 1, numberItem);

            table->setItem(row, 2,
                new QTableWidgetItem(root.isEmpty() ? tr("(archive root)") : root));

            auto* filesItem = new QTableWidgetItem(QString::number(filesByRoot.value(root).size()));
            filesItem->setTextAlignment(Qt::AlignCenter);
            table->setItem(row, 3, filesItem);

            auto* activeItem = new QTableWidgetItem;
            activeItem->setTextAlignment(Qt::AlignCenter);
            table->setItem(row, 4, activeItem);

            auto* overriddenItem = new QTableWidgetItem;
            overriddenItem->setTextAlignment(Qt::AlignCenter);
            table->setItem(row, 5, overriddenItem);

            table->setItem(row, 6, new QTableWidgetItem);
        }
    }

    const auto refreshSubpackagePreview = [table, roots, filesByRoot, this]() {
        if (roots.isEmpty())
            return;

        QSignalBlocker blocker(table);

        QHash<QString, int> finalOwner;
        for (int row = 0; row < roots.size(); ++row)
        {
            const QTableWidgetItem* useItem = table->item(row, 0);
            if (!useItem || useItem->checkState() != Qt::Checked)
                continue;

            const QSet<QString>& paths = filesByRoot.value(roots.at(row));
            for (const QString& path : paths)
                finalOwner.insert(path, row);
        }

        const QBrush usedBrush(QColor(46, 125, 50));
        const QBrush overriddenBrush(QColor(198, 40, 40));
        const QBrush disabledBrush(table->palette().color(QPalette::Disabled, QPalette::Text));

        for (int row = 0; row < roots.size(); ++row)
        {
            const QTableWidgetItem* useItem = table->item(row, 0);
            const bool selected = useItem && useItem->checkState() == Qt::Checked;
            const QSet<QString>& paths = filesByRoot.value(roots.at(row));

            int active = 0;
            if (selected)
            {
                for (const QString& path : paths)
                {
                    if (finalOwner.value(path, -1) == row)
                        ++active;
                }
            }

            const int overridden = selected ? paths.size() - active : 0;

            table->item(row, 4)->setText(selected ? QString::number(active) : QStringLiteral("—"));
            table->item(row, 5)->setText(selected ? QString::number(overridden) : QStringLiteral("—"));

            QString status;
            QBrush rowBrush;
            if (!selected)
            {
                status = tr("Not selected");
                rowBrush = disabledBrush;
            }
            else if (!paths.isEmpty() && active == 0)
            {
                status = tr("Fully overridden");
                rowBrush = overriddenBrush;
            }
            else if (overridden > 0)
            {
                status = tr("Partially overridden");
                rowBrush = usedBrush;
            }
            else
            {
                status = tr("Used");
                rowBrush = usedBrush;
            }

            table->item(row, 6)->setText(status);

            for (int column = 1; column < table->columnCount(); ++column)
                table->item(row, column)->setForeground(rowBrush);
        }
    };

    connect(table, &QTableWidget::itemChanged, &dialog,
        [refreshSubpackagePreview](QTableWidgetItem* item) {
            if (item && item->column() == 0)
                refreshSubpackagePreview();
        });

    refreshSubpackagePreview();

    auto* header = table->horizontalHeader();
    header->setSectionResizeMode(0, QHeaderView::ResizeToContents);
    header->setSectionResizeMode(1, QHeaderView::ResizeToContents);
    header->setSectionResizeMode(2, QHeaderView::Stretch);
    header->setSectionResizeMode(3, QHeaderView::ResizeToContents);
    header->setSectionResizeMode(4, QHeaderView::ResizeToContents);
    header->setSectionResizeMode(5, QHeaderView::ResizeToContents);
    header->setSectionResizeMode(6, QHeaderView::ResizeToContents);
    layout->addWidget(table);

    auto* buttons = new QDialogButtonBox(QDialogButtonBox::Ok | QDialogButtonBox::Cancel, &dialog);
    QPushButton* installButton = buttons->button(QDialogButtonBox::Ok);
    installButton->setText(tr("Install"));
    installButton->setEnabled(!roots.isEmpty());
    connect(buttons, &QDialogButtonBox::accepted, &dialog, &QDialog::accept);
    connect(buttons, &QDialogButtonBox::rejected, &dialog, &QDialog::reject);
    layout->addWidget(buttons);

    if (dialog.exec() != QDialog::Accepted)
        return;

    QString modName = modNameEdit->text().trimmed();
    static const QRegularExpression invalidModNameCharacters(QStringLiteral(R"([<>:"/\\|?*])"));

    const auto isValidModName = [](const QString& name) {
        return !name.isEmpty() && name != QLatin1String(".") && name != QLatin1String("..")
            && !invalidModNameCharacters.match(name).hasMatch()
            && !name.endsWith(' ') && !name.endsWith('.');
    };

    if (!isValidModName(modName))
    {
        QMessageBox::warning(this, tr("Install Mod"),
            tr("The mod name is invalid. Do not use path separators or characters reserved by Windows."));
        return;
    }

    QString destinationPath = overlayInstall
        ? normalizedOverlayTargetPath
        : QDir(modsDirectory).filePath(modName);
    bool replaceExisting = false;

    if (!overlayInstall && QFileInfo::exists(destinationPath))
    {
        QMessageBox collisionBox(QMessageBox::Question, tr("Mod Already Exists"),
            tr("A mod directory named \"%1\" already exists.\n\n"
               "You can replace it safely after the new version has been fully extracted, "
               "or install this archive under a different name.")
                .arg(modName),
            QMessageBox::NoButton, this);

        QPushButton* replaceButton = collisionBox.addButton(tr("Replace Existing"), QMessageBox::AcceptRole);
        QPushButton* installAsNewButton = collisionBox.addButton(tr("Install as New..."), QMessageBox::ActionRole);
        QPushButton* cancelButton = collisionBox.addButton(QMessageBox::Cancel);
        collisionBox.setDefaultButton(cancelButton);
        collisionBox.exec();

        if (collisionBox.clickedButton() == replaceButton)
        {
            replaceExisting = true;
        }
        else if (collisionBox.clickedButton() == installAsNewButton)
        {
            bool accepted = false;
            const QString suggestedName = modName + tr(" - Copy");
            const QString newName = QInputDialog::getText(this, tr("Install as New"),
                tr("New mod name:"), QLineEdit::Normal, suggestedName, &accepted).trimmed();

            if (!accepted)
                return;

            if (!isValidModName(newName))
            {
                QMessageBox::warning(this, tr("Install Mod"),
                    tr("The mod name is invalid. Do not use path separators or characters reserved by Windows."));
                return;
            }

            const QString newDestinationPath = QDir(modsDirectory).filePath(newName);
            if (QFileInfo::exists(newDestinationPath))
            {
                QMessageBox::warning(this, tr("Install Mod"),
                    tr("A mod directory named \"%1\" already exists.").arg(newName));
                return;
            }

            modName = newName;
            destinationPath = newDestinationPath;
        }
        else
        {
            return;
        }
    }

    QList<int> selectedRows;
    QHash<QString, int> finalOwner;

    for (int row = 0; row < roots.size(); ++row)
    {
        const QTableWidgetItem* useItem = table->item(row, 0);
        if (!useItem || useItem->checkState() != Qt::Checked)
            continue;

        selectedRows.push_back(row);
        const QSet<QString>& paths = filesByRoot.value(roots.at(row));
        for (const QString& path : paths)
            finalOwner.insert(path, row);
    }

    if (selectedRows.isEmpty() || finalOwner.isEmpty())
    {
        QMessageBox::warning(this, tr("Install Mod"),
            tr("Select at least one subpackage containing files."));
        return;
    }

    QTemporaryDir stagingDir(QDir(modsDirectory).filePath(QStringLiteral(".openmw-install-XXXXXX")));
    if (!stagingDir.isValid())
    {
        QMessageBox::critical(this, tr("Install Mod"),
            tr("Could not create a temporary installation directory inside the Mods Directory."));
        return;
    }

    bool installFailed = false;
    QString installError;
    int installedFiles = 0;
    QStringList installedRelativePaths;

    const auto extractSelectedWithSevenZip = [&]() -> bool {
        const QString executable = findSevenZipExecutable();
        if (executable.isEmpty())
        {
            installError = tr("Could not read archive data:\n%1")
                .arg(tr(
                    "No 7-Zip executable (7zz, 7z or 7za) was found in PATH."));
            return false;
        }

        QTemporaryDir extractedDir(
            QDir(modsDirectory).filePath(
                QStringLiteral(".openmw-7z-XXXXXX")));
        if (!extractedDir.isValid())
        {
            installError = tr(
                "Could not create a temporary installation directory inside the Mods Directory.");
            return false;
        }

        QProcess process;
        process.setProcessChannelMode(QProcess::SeparateChannels);
        process.start(executable,
            { QStringLiteral("x"), QStringLiteral("-y"),
                QStringLiteral("-bd"), QStringLiteral("-bb0"),
                QStringLiteral("-sccUTF-8"),
                QStringLiteral("-o%1").arg(extractedDir.path()),
                archivePath });

        if (!process.waitForStarted(5000))
        {
            installError = tr("Could not read archive data:\n%1")
                .arg(process.errorString());
            return false;
        }

        process.closeWriteChannel();
        process.waitForFinished(-1);

        const QString standardOutput
            = QString::fromUtf8(process.readAllStandardOutput()).trimmed();
        const QString standardError
            = QString::fromUtf8(process.readAllStandardError()).trimmed();

        if (process.exitStatus() != QProcess::NormalExit
            || process.exitCode() != 0)
        {
            QString details = standardError;
            if (details.isEmpty())
                details = standardOutput;
            if (details.isEmpty())
                details = process.errorString();

            installError = tr("Could not read archive data:\n%1")
                .arg(details);
            return false;
        }

        const QString canonicalExtractRoot
            = QFileInfo(extractedDir.path()).canonicalFilePath();
        if (canonicalExtractRoot.isEmpty())
        {
            installError = tr("Could not read archive data:\n%1")
                .arg(extractedDir.path());
            return false;
        }

        const QString extractRootPrefix
            = QDir::cleanPath(canonicalExtractRoot)
                + QLatin1Char('/');

        for (const QString& archiveEntryPath : filePaths)
        {
            bool extractedThisEntry = false;

            for (const int row : selectedRows)
            {
                const QString& root = roots.at(row);
                const QString prefix
                    = root.isEmpty() ? QString() : root + '/';

                QString relativePath;
                if (root.isEmpty())
                    relativePath = archiveEntryPath;
                else if (archiveEntryPath.startsWith(
                             prefix, Qt::CaseInsensitive))
                    relativePath = archiveEntryPath.mid(prefix.size());
                else
                    continue;

                relativePath.replace('\\', '/');
                while (relativePath.startsWith(
                    QLatin1String("./")))
                {
                    relativePath.remove(0, 2);
                }

                if (overlayInstall
                    && (relativePath.compare(
                            QStringLiteral("openmw-meta.ini"),
                            Qt::CaseInsensitive) == 0
                        || relativePath.compare(
                               QStringLiteral("meta.ini"),
                               Qt::CaseInsensitive) == 0))
                {
                    extractedThisEntry = true;
                    break;
                }

                const QString normalizedRelativePath
                    = relativePath.toLower();
                if (!filesByRoot.value(root).contains(
                        normalizedRelativePath)
                    || finalOwner.value(
                           normalizedRelativePath, -1) != row)
                {
                    continue;
                }

                const QStringList pathParts
                    = relativePath.split(
                        '/', Qt::KeepEmptyParts);
                bool unsafePath = relativePath.isEmpty()
                    || QDir::isAbsolutePath(relativePath);

                for (const QString& part : pathParts)
                {
                    if (part.isEmpty()
                        || part == QLatin1String(".")
                        || part == QLatin1String("..")
                        || part.contains(':'))
                    {
                        unsafePath = true;
                        break;
                    }
                }

                if (unsafePath)
                {
                    installError = tr(
                        "The archive contains an unsafe path:\n%1")
                        .arg(relativePath);
                    return false;
                }

                QString sourceRelativePath = archiveEntryPath;
                sourceRelativePath.replace('\\', '/');

                const QString sourcePath
                    = QDir(extractedDir.path())
                          .filePath(sourceRelativePath);
                const QFileInfo sourceInfo(sourcePath);

                if (!sourceInfo.exists()
                    || !sourceInfo.isFile()
                    || sourceInfo.isSymLink())
                {
                    installError = tr(
                        "7-Zip extraction did not produce the expected file:\n%1")
                        .arg(sourceRelativePath);
                    return false;
                }

                const QString canonicalSource
                    = QDir::cleanPath(
                        sourceInfo.canonicalFilePath());

                if (canonicalSource.isEmpty()
                    || !canonicalSource.startsWith(
                        extractRootPrefix))
                {
                    installError = tr(
                        "The archive contains an unsafe path:\n%1")
                        .arg(sourceRelativePath);
                    return false;
                }

                const QString outputPath
                    = QDir(stagingDir.path())
                          .filePath(relativePath);
                const QString outputDirectory
                    = QFileInfo(outputPath).absolutePath();

                if (!QDir().mkpath(outputDirectory))
                {
                    installError = tr(
                        "Could not create directory:\n%1")
                        .arg(outputDirectory);
                    return false;
                }

                if (QFileInfo::exists(outputPath)
                    && !QFile::remove(outputPath))
                {
                    installError = tr(
                        "Could not write file:\n%1")
                        .arg(outputPath);
                    return false;
                }

                if (!QFile::copy(sourcePath, outputPath))
                {
                    installError = tr(
                        "Could not write file:\n%1")
                        .arg(outputPath);
                    return false;
                }

                ++installedFiles;
                installedRelativePaths.push_back(relativePath);
                extractedThisEntry = true;
                break;
            }

            Q_UNUSED(extractedThisEntry);
        }

        return true;
    };

    if (use7ZipFallback)
    {
        if (!extractSelectedWithSevenZip())
            installFailed = true;
    }
    else
    {
        struct archive* installArchive = archive_read_new();
        if (!installArchive)
        {
            installFailed = true;
            installError = tr("Could not initialize the archive reader.");
        }
        else
        {
            archive_read_support_filter_all(installArchive);
            archive_read_support_format_all(installArchive);

            if (archive_read_open_filename(
                    installArchive, encodedPath.constData(),
                    10240) != ARCHIVE_OK)
            {
                const char* error
                    = archive_error_string(installArchive);
                installFailed = true;
                installError
                    = tr("Could not reopen the archive for installation:\n%1")
                          .arg(error
                                  ? QString::fromUtf8(error)
                                  : tr("Unknown error"));
            }
            else
            {
                struct archive_entry* installEntry = nullptr;
                int installReadResult = ARCHIVE_OK;

                while ((installReadResult
                           = archive_read_next_header(
                               installArchive, &installEntry))
                    == ARCHIVE_OK)
                {
                    if (archive_entry_filetype(installEntry)
                            != AE_IFREG
                        || archive_entry_symlink(installEntry)
                            != nullptr
                        || archive_entry_hardlink(installEntry)
                            != nullptr)
                    {
                        archive_read_data_skip(installArchive);
                        continue;
                    }

                    const char* rawPath
                        = archive_entry_pathname_utf8(installEntry);
                    if (!rawPath)
                        rawPath
                            = archive_entry_pathname(installEntry);
                    if (!rawPath)
                    {
                        archive_read_data_skip(installArchive);
                        continue;
                    }

                    QString archiveEntryPath
                        = QString::fromUtf8(rawPath).trimmed();
                    archiveEntryPath.replace('\\', '/');
                    while (archiveEntryPath.startsWith(
                        QLatin1String("./")))
                    {
                        archiveEntryPath.remove(0, 2);
                    }
                    while (archiveEntryPath.startsWith('/'))
                        archiveEntryPath.remove(0, 1);

                    bool extractedThisEntry = false;

                    for (const int row : selectedRows)
                    {
                        const QString& root = roots.at(row);
                        const QString prefix
                            = root.isEmpty()
                            ? QString()
                            : root + '/';

                        QString relativePath;
                        if (root.isEmpty())
                            relativePath = archiveEntryPath;
                        else if (archiveEntryPath.startsWith(
                                     prefix,
                                     Qt::CaseInsensitive))
                        {
                            relativePath
                                = archiveEntryPath.mid(
                                    prefix.size());
                        }
                        else
                        {
                            continue;
                        }

                        relativePath.replace('\\', '/');
                        while (relativePath.startsWith(
                            QLatin1String("./")))
                        {
                            relativePath.remove(0, 2);
                        }

                        if (overlayInstall
                            && (relativePath.compare(
                                    QStringLiteral(
                                        "openmw-meta.ini"),
                                    Qt::CaseInsensitive)
                                    == 0
                                || relativePath.compare(
                                       QStringLiteral(
                                           "meta.ini"),
                                       Qt::CaseInsensitive)
                                    == 0))
                        {
                            archive_read_data_skip(
                                installArchive);
                            extractedThisEntry = true;
                            break;
                        }

                        const QString normalizedRelativePath
                            = relativePath.toLower();
                        if (!filesByRoot.value(root).contains(
                                normalizedRelativePath)
                            || finalOwner.value(
                                   normalizedRelativePath,
                                   -1) != row)
                        {
                            continue;
                        }

                        const QStringList pathParts
                            = relativePath.split(
                                '/', Qt::KeepEmptyParts);
                        bool unsafePath
                            = relativePath.isEmpty()
                            || QDir::isAbsolutePath(
                                relativePath);
                        for (const QString& part : pathParts)
                        {
                            if (part.isEmpty()
                                || part
                                    == QLatin1String(".")
                                || part
                                    == QLatin1String("..")
                                || part.contains(':'))
                            {
                                unsafePath = true;
                                break;
                            }
                        }

                        if (unsafePath)
                        {
                            installFailed = true;
                            installError = tr(
                                "The archive contains an unsafe path:\n%1")
                                .arg(relativePath);
                            break;
                        }

                        const QString outputPath
                            = QDir(stagingDir.path())
                                  .filePath(relativePath);
                        const QString outputDirectory
                            = QFileInfo(outputPath)
                                  .absolutePath();

                        if (!QDir().mkpath(outputDirectory))
                        {
                            installFailed = true;
                            installError = tr(
                                "Could not create directory:\n%1")
                                .arg(outputDirectory);
                            break;
                        }

                        QFile outputFile(outputPath);
                        if (!outputFile.open(
                                QIODevice::WriteOnly
                                | QIODevice::Truncate))
                        {
                            installFailed = true;
                            installError = tr(
                                "Could not write file:\n%1")
                                .arg(outputPath);
                            break;
                        }

                        char buffer[64 * 1024];
                        while (true)
                        {
                            const la_ssize_t bytesRead
                                = archive_read_data(
                                    installArchive,
                                    buffer,
                                    sizeof(buffer));
                            if (bytesRead == 0)
                                break;

                            if (bytesRead < 0)
                            {
                                const char* error
                                    = archive_error_string(
                                        installArchive);
                                installFailed = true;
                                installError = tr(
                                    "Could not read archive data:\n%1")
                                    .arg(error
                                            ? QString::fromUtf8(
                                                  error)
                                            : tr(
                                                  "Unknown error"));
                                break;
                            }

                            if (outputFile.write(
                                    buffer, bytesRead)
                                != bytesRead)
                            {
                                installFailed = true;
                                installError = tr(
                                    "Could not write file:\n%1")
                                    .arg(outputPath);
                                break;
                            }
                        }

                        outputFile.close();

                        if (installFailed)
                            break;

                        ++installedFiles;
                        installedRelativePaths.push_back(
                            relativePath);
                        extractedThisEntry = true;
                        break;
                    }

                    if (installFailed)
                        break;

                    if (!extractedThisEntry)
                        archive_read_data_skip(
                            installArchive);
                }

                if (!installFailed
                    && installReadResult != ARCHIVE_EOF)
                {
                    const char* error
                        = archive_error_string(installArchive);
                    installFailed = true;
                    installError = tr(
                        "Could not finish reading the archive:\n%1")
                        .arg(error
                                ? QString::fromUtf8(error)
                                : tr("Unknown error"));
                }
            }

            archive_read_free(installArchive);
        }
    }

    if (installFailed)
    {
        QMessageBox::critical(this, tr("Install Mod"), installError);
        return;
    }

    if (overlayInstall)
    {
        if (!nexusMetadata || !nexusMetadata->mIsOverlay
            || nexusMetadata->mModId <= 0 || nexusMetadata->mTargetModId <= 0)
        {
            QMessageBox::critical(this, tr("Translation Overlay"),
                tr("The translation package metadata is incomplete."));
            return;
        }

        if (installedRelativePaths.isEmpty())
        {
            QMessageBox::warning(this, tr("Translation Overlay"),
                tr("The selected translation package did not contain installable files."));
            return;
        }

        const QString managerMetadataPath
            = QDir(destinationPath).filePath(QStringLiteral("openmw-meta.ini"));
        QSettings existingMetadata(managerMetadataPath, QSettings::IniFormat);
        const QString packageGroup
            = QStringLiteral("Package.%1").arg(nexusMetadata->mModId);

        if (existingMetadata.childGroups().contains(packageGroup, Qt::CaseInsensitive))
        {
            QMessageBox::information(this, tr("Translation Overlay"),
                tr("This translation package is already installed in the selected base mod."));
            return;
        }

        QHash<QString, QString> overlayPathsByKey;
        for (const QString& relativePath : installedRelativePaths)
            overlayPathsByKey.insert(relativePath.toLower(), relativePath);

        QStringList overlayRelativePaths = overlayPathsByKey.values();
        std::sort(overlayRelativePaths.begin(), overlayRelativePaths.end(),
            [](const QString& lhs, const QString& rhs) {
                return lhs.compare(rhs, Qt::CaseInsensitive) < 0;
            });

        QTemporaryDir overlayBackup(
            QDir(modsDirectory).filePath(QStringLiteral(".openmw-overlay-backup-XXXXXX")));
        if (!overlayBackup.isValid())
        {
            QMessageBox::critical(this, tr("Translation Overlay"),
                tr("Could not create a temporary backup for the translation overlay."));
            return;
        }

        const QString metadataBackupPath
            = QDir(overlayBackup.path()).filePath(QStringLiteral("__openmw-meta.ini"));
        if (!QFile::copy(managerMetadataPath, metadataBackupPath))
        {
            QMessageBox::critical(this, tr("Translation Overlay"),
                tr("Could not back up the managed mod metadata before applying the translation."));
            return;
        }

        bool overlayFailed = false;
        QString overlayError;

        for (const QString& relativePath : overlayRelativePaths)
        {
            const QString sourcePath = QDir(stagingDir.path()).filePath(relativePath);
            const QFileInfo sourceInfo(sourcePath);
            if (!sourceInfo.isFile() || sourceInfo.isSymLink())
            {
                overlayFailed = true;
                overlayError = tr("The staged translation file is not a safe regular file:\n%1")
                                   .arg(relativePath);
                break;
            }

            const QString destinationFilePath = QDir(destinationPath).filePath(relativePath);
            const QFileInfo destinationInfo(destinationFilePath);
            if (!destinationInfo.exists())
                continue;

            if (!destinationInfo.isFile() || destinationInfo.isSymLink())
            {
                overlayFailed = true;
                overlayError = tr("The translation would replace a non-regular file:\n%1")
                                   .arg(relativePath);
                break;
            }

            const QString backupFilePath
                = QDir(overlayBackup.path()).filePath(relativePath);
            if (!QDir().mkpath(QFileInfo(backupFilePath).absolutePath())
                || !QFile::copy(destinationFilePath, backupFilePath))
            {
                overlayFailed = true;
                overlayError = tr("Could not back up a file before applying the translation:\n%1")
                                   .arg(relativePath);
                break;
            }
        }

        if (overlayFailed)
        {
            QMessageBox::critical(this, tr("Translation Overlay"), overlayError);
            return;
        }

        const auto rollbackOverlay = [&]() -> bool
        {
            bool restored = true;

            for (const QString& relativePath : overlayRelativePaths)
            {
                const QString destinationFilePath
                    = QDir(destinationPath).filePath(relativePath);
                if (QFileInfo::exists(destinationFilePath)
                    && !QFile::remove(destinationFilePath))
                {
                    restored = false;
                }

                const QString backupFilePath
                    = QDir(overlayBackup.path()).filePath(relativePath);
                if (QFileInfo(backupFilePath).isFile())
                {
                    if (!QDir().mkpath(QFileInfo(destinationFilePath).absolutePath())
                        || !QFile::copy(backupFilePath, destinationFilePath))
                    {
                        restored = false;
                    }
                }
            }

            if (QFileInfo::exists(managerMetadataPath)
                && !QFile::remove(managerMetadataPath))
            {
                restored = false;
            }

            if (!QFile::copy(metadataBackupPath, managerMetadataPath))
                restored = false;

            return restored;
        };

        for (const QString& relativePath : overlayRelativePaths)
        {
            const QString sourcePath = QDir(stagingDir.path()).filePath(relativePath);
            const QString destinationFilePath
                = QDir(destinationPath).filePath(relativePath);

            if (!QDir().mkpath(QFileInfo(destinationFilePath).absolutePath()))
            {
                overlayFailed = true;
                overlayError = tr("Could not create a directory for the translation file:\n%1")
                                   .arg(relativePath);
                break;
            }

            if (QFileInfo::exists(destinationFilePath)
                && !QFile::remove(destinationFilePath))
            {
                overlayFailed = true;
                overlayError = tr("Could not replace a base mod file with the translation:\n%1")
                                   .arg(relativePath);
                break;
            }

            if (!QFile::copy(sourcePath, destinationFilePath))
            {
                overlayFailed = true;
                overlayError = tr("Could not install the translation file:\n%1")
                                   .arg(relativePath);
                break;
            }
        }

        if (overlayFailed)
        {
            const bool rollbackOk = rollbackOverlay();
            QMessageBox::critical(this, tr("Translation Overlay"),
                rollbackOk
                    ? tr("The translation could not be installed. The base mod was restored.\n%1")
                          .arg(overlayError)
                    : tr("The translation could not be installed and automatic rollback was incomplete.\n%1")
                          .arg(overlayError));
            return;
        }

        QSettings overlayMetadata(managerMetadataPath, QSettings::IniFormat);
        QSet<QString> newOwnedKeys;
        for (auto it = overlayPathsByKey.cbegin(); it != overlayPathsByKey.cend(); ++it)
            newOwnedKeys.insert(it.key());

        const QStringList existingGroups = overlayMetadata.childGroups();
        for (const QString& group : existingGroups)
        {
            if (!group.startsWith(QStringLiteral("Package."), Qt::CaseInsensitive)
                || group.compare(packageGroup, Qt::CaseInsensitive) == 0)
            {
                continue;
            }

            overlayMetadata.beginGroup(group);
            const QStringList ownedFiles
                = overlayMetadata.value(QStringLiteral("files")).toStringList();
            QStringList filteredFiles;
            for (const QString& path : ownedFiles)
            {
                if (!newOwnedKeys.contains(path.toLower()))
                    filteredFiles.push_back(path);
            }
            overlayMetadata.setValue(QStringLiteral("files"), filteredFiles);
            overlayMetadata.endGroup();
        }

        overlayMetadata.beginGroup(packageGroup);
        overlayMetadata.setValue(QStringLiteral("type"),
            nexusMetadata->mPackageType.isEmpty()
                ? QStringLiteral("overlay")
                : nexusMetadata->mPackageType);
        overlayMetadata.setValue(QStringLiteral("gamename"), QStringLiteral("morrowind"));
        overlayMetadata.setValue(QStringLiteral("modid"), nexusMetadata->mModId);
        overlayMetadata.setValue(QStringLiteral("fileid"), nexusMetadata->mFileId);
        overlayMetadata.setValue(QStringLiteral("version"), nexusMetadata->mVersion);
        overlayMetadata.setValue(QStringLiteral("author"), nexusMetadata->mAuthor);
        overlayMetadata.setValue(QStringLiteral("uploadedby"), nexusMetadata->mUploadedBy);
        overlayMetadata.setValue(QStringLiteral("nexusname"), nexusMetadata->mNexusName);
        overlayMetadata.setValue(QStringLiteral("nexusfilename"), nexusMetadata->mNexusFileName);
        overlayMetadata.setValue(QStringLiteral("installationfile"), nexusMetadata->mInstallationFile);
        overlayMetadata.setValue(QStringLiteral("filesize"), nexusMetadata->mFileSize);
        overlayMetadata.setValue(QStringLiteral("installed"),
            QDateTime::currentDateTime().toString(Qt::ISODate));
        overlayMetadata.setValue(QStringLiteral("nexusurl"),
            QStringLiteral("https://www.nexusmods.com/morrowind/mods/%1")
                .arg(nexusMetadata->mModId));
        overlayMetadata.setValue(QStringLiteral("targetmodid"), nexusMetadata->mTargetModId);
        overlayMetadata.setValue(QStringLiteral("targetversion"), nexusMetadata->mTargetVersion);
        overlayMetadata.setValue(QStringLiteral("files"), overlayRelativePaths);
        overlayMetadata.endGroup();
        overlayMetadata.sync();

        if (overlayMetadata.status() != QSettings::NoError)
        {
            const bool rollbackOk = rollbackOverlay();
            QMessageBox::critical(this, tr("Translation Overlay"),
                rollbackOk
                    ? tr("Could not save translation package metadata. The base mod was restored.")
                    : tr("Could not save translation package metadata and automatic rollback was incomplete."));
            return;
        }

        if (installedPathOut)
            *installedPathOut = destinationPath;

        refreshDataFilesView();
        mMainDialog->writeSettings();

        QMessageBox::information(this, tr("Translation Installed"),
            tr("Installed %1 translation files into:\n%2")
                .arg(overlayRelativePaths.size())
                .arg(destinationPath));
        return;
    }

    const QString stagingLeafName = QFileInfo(stagingDir.path()).fileName();
    QDir modsRoot(modsDirectory);

    QString backupLeafName;
    QString backupPath;

    if (replaceExisting)
    {
        backupLeafName = QStringLiteral(".openmw-backup-%1")
            .arg(QUuid::createUuid().toString(QUuid::WithoutBraces));
        backupPath = modsRoot.filePath(backupLeafName);

        if (!modsRoot.rename(modName, backupLeafName))
        {
            QMessageBox::critical(this, tr("Install Mod"),
                tr("Could not move the existing mod to a temporary backup:\n%1").arg(destinationPath));
            return;
        }
    }

    if (!modsRoot.rename(stagingLeafName, modName))
    {
        if (replaceExisting)
        {
            if (!modsRoot.rename(backupLeafName, modName))
            {
                QMessageBox::critical(this, tr("Install Mod"),
                    tr("Could not finalize the new installation and could not automatically restore the old mod.\n"
                       "The backup is still available at:\n%1")
                        .arg(backupPath));
                return;
            }
        }

        QMessageBox::critical(this, tr("Install Mod"),
            tr("Could not finalize the installation in:\n%1").arg(destinationPath));
        return;
    }

    bool backupRemoved = true;
    if (replaceExisting)
        backupRemoved = QDir(backupPath).removeRecursively();

    QString nexusMetadataError;
    if (nexusMetadata)
    {
        const QString metadataPath = QDir(destinationPath).filePath(QStringLiteral("openmw-meta.ini"));
        QSettings metadata(metadataPath, QSettings::IniFormat);
        metadata.setValue(QStringLiteral("gamename"), QStringLiteral("morrowind"));
        metadata.setValue(QStringLiteral("modid"), nexusMetadata->mModId);
        metadata.setValue(QStringLiteral("fileid"), nexusMetadata->mFileId);
        metadata.setValue(QStringLiteral("version"), nexusMetadata->mVersion);
        metadata.setValue(QStringLiteral("author"), nexusMetadata->mAuthor);
        metadata.setValue(QStringLiteral("uploadedby"), nexusMetadata->mUploadedBy);
        metadata.setValue(QStringLiteral("nexusname"), nexusMetadata->mNexusName);
        metadata.setValue(QStringLiteral("nexusfilename"), nexusMetadata->mNexusFileName);
        metadata.setValue(QStringLiteral("installationfile"), nexusMetadata->mInstallationFile);
        metadata.setValue(QStringLiteral("filesize"), nexusMetadata->mFileSize);
        metadata.setValue(QStringLiteral("installed"), QDateTime::currentDateTime().toString(Qt::ISODate));
        metadata.setValue(QStringLiteral("nexusurl"),
            QStringLiteral("https://www.nexusmods.com/morrowind/mods/%1").arg(nexusMetadata->mModId));
        metadata.setValue(QStringLiteral("description"), nexusMetadata->mDescription);
        metadata.setValue(QStringLiteral("categoryid"), nexusMetadata->mCategoryId);
        metadata.setValue(QStringLiteral("categoryname"), nexusMetadata->mCategoryName);
        metadata.setValue(QStringLiteral("filecategory"), nexusMetadata->mFileCategory);
        metadata.setValue(QStringLiteral("endorsed"), false);
        metadata.setValue(QStringLiteral("latestfileid"), nexusMetadata->mFileId);
        metadata.setValue(QStringLiteral("latestversion"), nexusMetadata->mVersion);
        metadata.setValue(QStringLiteral("hasupdate"), false);
        metadata.setValue(QStringLiteral("ignoreupdate"), false);
        metadata.setValue(QStringLiteral("ignoredversion"), QString());
        metadata.setValue(QStringLiteral("missingrequirements"), QString());
        metadata.setValue(QStringLiteral("nexusrequirements"), QString());
        metadata.setValue(QStringLiteral("ignoredrequirements"), QString());
        metadata.setValue(QStringLiteral("rootfolder"), false);
        metadata.setValue(QStringLiteral("fromcollection"), false);
        metadata.sync();

        if (metadata.status() != QSettings::NoError)
            nexusMetadataError = metadataPath;
    }

    if (installedPathOut)
        *installedPathOut = destinationPath;

    refreshDataFilesView();
    mMainDialog->writeSettings();

    if (replaceExisting && !backupRemoved)
    {
        QMessageBox::warning(this, tr("Mod Replaced"),
            tr("The mod was replaced successfully, but the temporary backup could not be removed:\n%1")
                .arg(backupPath));
    }
    else if (replaceExisting)
    {
        QMessageBox::information(this, tr("Mod Replaced"),
            tr("Replaced the existing mod with %1 files in:\n%2").arg(installedFiles).arg(destinationPath));
    }
    else
    {
        QMessageBox::information(this, tr("Mod Installed"),
            tr("Installed %1 files to:\n%2").arg(installedFiles).arg(destinationPath));
    }

    if (!nexusMetadataError.isEmpty())
    {
        QMessageBox::warning(this, tr("Nexus Mods Metadata"),
            tr("Could not save Nexus Mods metadata to:\n%1").arg(nexusMetadataError));
    }
}

void Launcher::DataFilesPage::showNxmHandlerSettings()
{
#ifndef Q_OS_LINUX
    return;
#else
    const QString currentHandler = currentNxmHandlerDesktopId();
    const bool isOpenMw = currentHandler.compare(
        nxmDesktopEntryId(), Qt::CaseInsensitive) == 0;

    const QString previousHandler = mLauncherSettings.getPreviousNxmHandler().trimmed();
    const bool previousHandlerIsUs = previousHandler.compare(
        nxmDesktopEntryId(), Qt::CaseInsensitive) == 0;
    const bool previousHandlerAvailable = !previousHandler.isEmpty()
        && !previousHandlerIsUs && desktopEntryExists(previousHandler);

    QString status;
    if (currentHandler.isEmpty())
    {
        status = tr("No default NXM handler is currently configured.");
    }
    else if (isOpenMw)
    {
        status = tr("Current NXM handler: OpenMW Launcher");
    }
    else
    {
        const QString displayName = desktopEntryDisplayName(currentHandler);
        status = tr("Current NXM handler: %1\n%2")
                     .arg(displayName, currentHandler);
    }

    if (isOpenMw && previousHandlerAvailable)
    {
        status += tr("\n\nPrevious NXM handler: %1\n%2")
                      .arg(desktopEntryDisplayName(previousHandler), previousHandler);
    }
    else if (isOpenMw && !previousHandler.isEmpty() && !previousHandlerIsUs)
    {
        status += tr("\n\nSaved previous NXM handler is no longer available:\n%1")
                      .arg(previousHandler);
    }

    QMessageBox dialog(this);
    dialog.setWindowTitle(tr("NXM Handler"));
    dialog.setIcon(QMessageBox::Information);
    dialog.setText(status);
    if (isOpenMw)
    {
        dialog.setInformativeText(
            tr("OpenMW Launcher is already the default application for nxm:// links. "
               "Nexus Mods Mod Manager Download links will be opened in this launcher."));
    }
    else
    {
        dialog.setInformativeText(
            tr("Only one application can be the default handler for nxm:// links. "
               "Changing it will send future Nexus Mods Mod Manager Download links "
               "to OpenMW Launcher."));
    }

    QPushButton* setDefaultButton = nullptr;
    QPushButton* restorePreviousButton = nullptr;

    if (!isOpenMw)
    {
        setDefaultButton = dialog.addButton(
            tr("Set OpenMW Launcher as Default"), QMessageBox::AcceptRole);
    }
    else if (previousHandlerAvailable)
    {
        restorePreviousButton = dialog.addButton(
            tr("Restore Previous Handler"), QMessageBox::AcceptRole);
    }

    dialog.addButton(QMessageBox::Close);
    dialog.exec();

    if (setDefaultButton && dialog.clickedButton() == setDefaultButton)
    {
        QString error;
        if (!setOpenMwAsDefaultNxmHandler(error))
        {
            QMessageBox::critical(this, tr("NXM Handler"),
                tr("Could not set OpenMW Launcher as the default NXM handler.\n%1")
                    .arg(error));
            return;
        }

        if (!currentHandler.isEmpty()
            && currentHandler.compare(nxmDesktopEntryId(), Qt::CaseInsensitive) != 0)
        {
            mLauncherSettings.setPreviousNxmHandler(currentHandler);
            mMainDialog->writeSettings();
        }

        QMessageBox::information(this, tr("NXM Handler"),
            tr("OpenMW Launcher is now the default application for nxm:// links."));
        return;
    }

    if (restorePreviousButton && dialog.clickedButton() == restorePreviousButton)
    {
        QString error;
        if (!setDefaultNxmHandler(previousHandler, error))
        {
            QMessageBox::critical(this, tr("NXM Handler"),
                tr("Could not restore the previous NXM handler.\n%1").arg(error));
            return;
        }

        mLauncherSettings.setPreviousNxmHandler(QString());
        mMainDialog->writeSettings();

        QMessageBox::information(this, tr("NXM Handler"),
            tr("The previous NXM handler has been restored: %1")
                .arg(desktopEntryDisplayName(previousHandler)));
    }
#endif
}

bool Launcher::DataFilesPage::ensureNxmHandlerForDownload()
{
#ifndef Q_OS_LINUX
    return true;
#else
    const QString currentHandler = currentNxmHandlerDesktopId();
    if (currentHandler.compare(nxmDesktopEntryId(), Qt::CaseInsensitive) == 0)
        return true;

    QString currentText;
    if (currentHandler.isEmpty())
    {
        currentText = tr("No default NXM handler is currently configured.");
    }
    else
    {
        currentText = tr("Mod Manager Download links are currently handled by:\n%1")
                          .arg(desktopEntryDisplayName(currentHandler));
    }

    const QMessageBox::StandardButton answer = QMessageBox::question(
        this, tr("NXM Handler"),
        tr("%1\n\nOpenMW Launcher must be the default NXM handler to receive "
           "this download. Set OpenMW Launcher as default now?")
            .arg(currentText),
        QMessageBox::Yes | QMessageBox::No, QMessageBox::Yes);

    if (answer != QMessageBox::Yes)
        return false;

    QString error;
    if (!setOpenMwAsDefaultNxmHandler(error))
    {
        QMessageBox::critical(this, tr("NXM Handler"),
            tr("Could not set OpenMW Launcher as the default NXM handler.\n%1")
                .arg(error));
        return false;
    }

    if (!currentHandler.isEmpty()
        && currentHandler.compare(nxmDesktopEntryId(), Qt::CaseInsensitive) != 0)
    {
        mLauncherSettings.setPreviousNxmHandler(currentHandler);
        mMainDialog->writeSettings();
    }

    return true;
#endif
}

void Launcher::DataFilesPage::connectNexusMods()
{
    if (!ensureNexusConnected())
        return;

    lookupNexusMod();
}

bool Launcher::DataFilesPage::ensureNexusConnected()
{
    if (!mNexusApiKey.isEmpty())
        return true;

    bool accepted = false;
    const QString enteredKey = QInputDialog::getText(this, tr("Connect to Nexus Mods"),
        tr("Personal API key:"), QLineEdit::Password, QString(), &accepted).trimmed();

    if (!accepted)
        return false;

    if (enteredKey.isEmpty())
    {
        QMessageBox::warning(this, tr("Nexus Mods"), tr("Enter a Personal API key."));
        return false;
    }

    QNetworkRequest request(QUrl(QStringLiteral("https://api.nexusmods.com/v1/users/validate.json")));
    request.setRawHeader("apikey", enteredKey.toUtf8());
    request.setRawHeader("Application-Name", QByteArrayLiteral("OpenMW-Runtime-Localization-Fork"));
    request.setRawHeader("Application-Version", QByteArrayLiteral("0.4-dev"));

    QNetworkAccessManager networkManager;
    QNetworkReply* reply = networkManager.get(request);

    QEventLoop eventLoop;
    connect(reply, &QNetworkReply::finished, &eventLoop, &QEventLoop::quit);
    eventLoop.exec();

    const QByteArray responseData = reply->readAll();
    const int httpStatus = reply->attribute(QNetworkRequest::HttpStatusCodeAttribute).toInt();
    const QString networkError = reply->errorString();
    const bool requestSucceeded
        = reply->error() == QNetworkReply::NoError && httpStatus >= 200 && httpStatus < 300;
    reply->deleteLater();

    QJsonParseError parseError;
    const QJsonDocument document = QJsonDocument::fromJson(responseData, &parseError);
    const QJsonObject object = document.isObject() ? document.object() : QJsonObject();

    if (!requestSucceeded)
    {
        QString details = object.value(QStringLiteral("message")).toString();
        if (details.isEmpty())
            details = networkError;

        QMessageBox::critical(this, tr("Nexus Mods"),
            tr("Could not connect to Nexus Mods.\nHTTP status: %1\n%2")
                .arg(httpStatus)
                .arg(details));
        return false;
    }

    if (parseError.error != QJsonParseError::NoError || object.isEmpty())
    {
        QMessageBox::critical(this, tr("Nexus Mods"),
            tr("Nexus Mods returned an invalid response."));
        return false;
    }

    const QString userName = object.value(QStringLiteral("name")).toString();
    if (userName.isEmpty())
    {
        QMessageBox::critical(this, tr("Nexus Mods"),
            tr("The API key was accepted, but the Nexus Mods account name was not returned."));
        return false;
    }

    mNexusApiKey = enteredKey;
    mNexusUserName = userName;
    mNexusPremium = object.value(QStringLiteral("is_premium")).toBool(false);
    mNexusUserId = object.value(QStringLiteral("user_id")).toVariant().toLongLong();

    QMessageBox::information(this, tr("Nexus Mods Connected"),
        tr("Connected to Nexus Mods as: %1\nAccount: %2\n\n"
           "The Personal API key is kept only for this launcher session.")
            .arg(mNexusUserName)
            .arg(mNexusPremium ? tr("Premium") : tr("Free")));

    return true;
}

void Launcher::DataFilesPage::lookupNexusMod()
{
    if (!ensureNexusConnected())
        return;

    bool accepted = false;
    const QString input = QInputDialog::getText(this, tr("Nexus Mods - Find Mod"),
        tr("Morrowind Mod ID or Nexus Mods URL:"), QLineEdit::Normal,
        QStringLiteral("60029"), &accepted).trimmed();

    if (!accepted)
        return;

    int modId = 0;
    bool idOk = false;

    const QRegularExpression idExpression(QStringLiteral(R"(^\s*(\d+)\s*$)"));
    const QRegularExpression urlExpression(
        QStringLiteral(R"(nexusmods\.com/morrowind/mods/(\d+))"),
        QRegularExpression::CaseInsensitiveOption);

    const QRegularExpressionMatch idMatch = idExpression.match(input);
    if (idMatch.hasMatch())
        modId = idMatch.captured(1).toInt(&idOk);
    else
    {
        const QRegularExpressionMatch urlMatch = urlExpression.match(input);
        if (urlMatch.hasMatch())
            modId = urlMatch.captured(1).toInt(&idOk);
    }

    if (!idOk || modId <= 0)
    {
        QMessageBox::warning(this, tr("Nexus Mods"),
            tr("Enter a valid Morrowind Mod ID or a Nexus Mods Morrowind mod URL."));
        return;
    }

    QNetworkAccessManager networkManager;

    auto getJson = [&](const QUrl& url, QJsonDocument& document, QString& errorText,
                       QByteArray* hourlyRemaining = nullptr, QByteArray* dailyRemaining = nullptr) -> bool
    {
        QNetworkRequest request(url);
        request.setRawHeader("apikey", mNexusApiKey.toUtf8());
        request.setRawHeader("Application-Name", QByteArrayLiteral("OpenMW-Runtime-Localization-Fork"));
        request.setRawHeader("Application-Version", QByteArrayLiteral("0.4-dev"));

        QNetworkReply* reply = networkManager.get(request);
        QEventLoop eventLoop;
        connect(reply, &QNetworkReply::finished, &eventLoop, &QEventLoop::quit);
        eventLoop.exec();

        if (hourlyRemaining)
            *hourlyRemaining = reply->rawHeader("x-rl-hourly-remaining");
        if (dailyRemaining)
            *dailyRemaining = reply->rawHeader("x-rl-daily-remaining");

        const QByteArray responseData = reply->readAll();
        const int httpStatus = reply->attribute(QNetworkRequest::HttpStatusCodeAttribute).toInt();
        const QNetworkReply::NetworkError networkErrorCode = reply->error();
        const QString networkError = reply->errorString();
        reply->deleteLater();

        QJsonParseError parseError;
        document = QJsonDocument::fromJson(responseData, &parseError);

        if (networkErrorCode != QNetworkReply::NoError || httpStatus < 200 || httpStatus >= 300)
        {
            QString apiMessage;
            if (document.isObject())
                apiMessage = document.object().value(QStringLiteral("message")).toString();

            errorText = tr("HTTP status: %1\n%2")
                            .arg(httpStatus)
                            .arg(apiMessage.isEmpty() ? networkError : apiMessage);
            return false;
        }

        if (parseError.error != QJsonParseError::NoError)
        {
            errorText = tr("Nexus Mods returned an invalid JSON response.");
            return false;
        }

        return true;
    };

    auto postGraphQl = [&](const QString& query, const QJsonObject& variables,
                           QJsonObject& graphDataOut, QString& errorText,
                           QByteArray* hourlyRemaining = nullptr,
                           QByteArray* dailyRemaining = nullptr) -> bool
    {
        QNetworkRequest request(
            QUrl(QStringLiteral("https://api.nexusmods.com/v2/graphql")));
        request.setRawHeader("apikey", mNexusApiKey.toUtf8());
        request.setRawHeader(
            "Application-Name", QByteArrayLiteral("OpenMW-Runtime-Localization-Fork"));
        request.setRawHeader("Application-Version", QByteArrayLiteral("0.4-dev"));
        request.setHeader(
            QNetworkRequest::ContentTypeHeader, QStringLiteral("application/json"));

        QJsonObject body;
        body.insert(QStringLiteral("query"), query);
        body.insert(QStringLiteral("variables"), variables);

        QNetworkReply* reply = networkManager.post(
            request, QJsonDocument(body).toJson(QJsonDocument::Compact));

        QEventLoop eventLoop;
        connect(reply, &QNetworkReply::finished, &eventLoop, &QEventLoop::quit);
        eventLoop.exec();

        if (hourlyRemaining)
            *hourlyRemaining = reply->rawHeader("x-rl-hourly-remaining");
        if (dailyRemaining)
            *dailyRemaining = reply->rawHeader("x-rl-daily-remaining");

        const QByteArray responseData = reply->readAll();
        const int httpStatus
            = reply->attribute(QNetworkRequest::HttpStatusCodeAttribute).toInt();
        const QNetworkReply::NetworkError networkErrorCode = reply->error();
        const QString networkError = reply->errorString();
        reply->deleteLater();

        QJsonParseError parseError;
        const QJsonDocument document = QJsonDocument::fromJson(responseData, &parseError);

        if (parseError.error != QJsonParseError::NoError || !document.isObject())
        {
            errorText = tr("Nexus Mods returned an invalid GraphQL response.");
            return false;
        }

        const QJsonObject response = document.object();
        const QJsonArray graphErrors = response.value(QStringLiteral("errors")).toArray();

        if (networkErrorCode != QNetworkReply::NoError || httpStatus < 200 || httpStatus >= 300)
        {
            QString apiMessage = response.value(QStringLiteral("message")).toString();
            if (apiMessage.isEmpty() && !graphErrors.isEmpty())
                apiMessage = graphErrors.at(0).toObject()
                                 .value(QStringLiteral("message")).toString();
            if (apiMessage.isEmpty())
                apiMessage = networkError;

            errorText = tr("HTTP status: %1\n%2").arg(httpStatus).arg(apiMessage);
            return false;
        }

        if (!graphErrors.isEmpty())
        {
            errorText = graphErrors.at(0).toObject()
                            .value(QStringLiteral("message")).toString();
            if (errorText.isEmpty())
                errorText = tr("Nexus Mods returned a GraphQL error.");
            return false;
        }

        const QJsonValue dataValue = response.value(QStringLiteral("data"));
        if (!dataValue.isObject())
        {
            errorText = tr("Nexus Mods GraphQL response did not contain data.");
            return false;
        }

        graphDataOut = dataValue.toObject();
        return true;
    };

    QJsonDocument modDocument;
    QString errorText;
    QByteArray hourlyRemaining;
    QByteArray dailyRemaining;

    const QUrl modUrl(QStringLiteral("https://api.nexusmods.com/v1/games/morrowind/mods/%1.json").arg(modId));
    if (!getJson(modUrl, modDocument, errorText, &hourlyRemaining, &dailyRemaining)
        || !modDocument.isObject())
    {
        QMessageBox::critical(this, tr("Nexus Mods"),
            tr("Could not retrieve mod information.\n%1").arg(errorText));
        return;
    }

    QJsonDocument filesDocument;
    const QUrl filesUrl(
        QStringLiteral("https://api.nexusmods.com/v1/games/morrowind/mods/%1/files.json").arg(modId));
    if (!getJson(filesUrl, filesDocument, errorText, &hourlyRemaining, &dailyRemaining)
        || !filesDocument.isObject())
    {
        QMessageBox::critical(this, tr("Nexus Mods"),
            tr("Could not retrieve the mod file list.\n%1").arg(errorText));
        return;
    }

    const QJsonObject mod = modDocument.object();
    const QJsonArray allFiles = filesDocument.object().value(QStringLiteral("files")).toArray();

    QJsonArray files;
    for (const QJsonValue& value : allFiles)
    {
        const QJsonObject file = value.toObject();
        const QString categoryName
            = file.value(QStringLiteral("category_name")).toString().trimmed();

        if (categoryName.compare(QStringLiteral("ARCHIVED"), Qt::CaseInsensitive) == 0)
            continue;

        files.append(file);
    }

    // Translation discovery intentionally combines two independent Nexus facts:
    // 1) the candidate mod requires this exact base mod;
    // 2) the candidate is tagged globally as "Translation".
    // This avoids language/name heuristics and keeps unrelated patches/add-ons out.
    constexpr int nexusGraphPageSize = 80;
    QVector<QJsonObject> translations;
    QString translationsError;
    bool translationsLookupOk = true;
    QSet<qint64> dependentModIds;

    static QString morrowindGraphGameId;
    if (morrowindGraphGameId.isEmpty())
    {
        const QString gameIdQuery = QString::fromLatin1(R"GRAPHQL(
query MorrowindGameId($domainName: String!) {
  game(domainName: $domainName) {
    id
  }
}
)GRAPHQL");

        QJsonObject variables;
        variables.insert(QStringLiteral("domainName"), QStringLiteral("morrowind"));

        QJsonObject graphData;
        if (!postGraphQl(gameIdQuery, variables, graphData, translationsError,
                &hourlyRemaining, &dailyRemaining))
        {
            translationsLookupOk = false;
        }
        else
        {
            morrowindGraphGameId
                = graphData.value(QStringLiteral("game")).toObject()
                      .value(QStringLiteral("id")).toVariant().toString().trimmed();

            if (morrowindGraphGameId.isEmpty())
            {
                translationsError = tr("Nexus Mods GraphQL did not return the Morrowind game ID.");
                translationsLookupOk = false;
            }
        }
    }

    const QString requiringModsQuery = QString::fromLatin1(R"GRAPHQL(
query AvailableTranslationDependents(
  $modId: ID!,
  $gameId: ID!,
  $offset: Int!,
  $count: Int!
) {
  mod(modId: $modId, gameId: $gameId) {
    modRequirements {
      modsRequiringThisMod(offset: $offset, count: $count) {
        totalCount
        nodes {
          modId
        }
      }
    }
  }
}
)GRAPHQL");

    int requiringOffset = 0;
    while (translationsLookupOk)
    {
        QJsonObject variables;
        variables.insert(QStringLiteral("modId"), QString::number(modId));
        variables.insert(QStringLiteral("gameId"), morrowindGraphGameId);
        variables.insert(QStringLiteral("offset"), requiringOffset);
        variables.insert(QStringLiteral("count"), nexusGraphPageSize);

        QJsonObject graphData;
        if (!postGraphQl(requiringModsQuery, variables, graphData, translationsError,
                &hourlyRemaining, &dailyRemaining))
        {
            translationsLookupOk = false;
            break;
        }

        const QJsonObject baseMod = graphData.value(QStringLiteral("mod")).toObject();
        if (baseMod.isEmpty())
        {
            translationsError = tr("Nexus Mods GraphQL could not find the base mod.");
            translationsLookupOk = false;
            break;
        }

        const QJsonObject requiringPage
            = baseMod.value(QStringLiteral("modRequirements")).toObject()
                  .value(QStringLiteral("modsRequiringThisMod")).toObject();
        const QJsonArray nodes = requiringPage.value(QStringLiteral("nodes")).toArray();
        const int totalCount = requiringPage.value(QStringLiteral("totalCount")).toInt();

        for (const QJsonValue& value : nodes)
        {
            const qint64 dependentModId
                = value.toObject().value(QStringLiteral("modId")).toVariant().toLongLong();
            if (dependentModId > 0)
                dependentModIds.insert(dependentModId);
        }

        requiringOffset += nodes.size();
        if (nodes.isEmpty() || requiringOffset >= totalCount)
            break;
    }

    // The Translation-tag catalog is identical for every opened Morrowind mod,
    // so fetch it once per launcher session instead of re-querying it for every
    // dependent mod (important for large bases such as Tamriel Rebuilt).
    static bool translationCatalogLoaded = false;
    static QJsonArray translationCatalog;

    if (translationsLookupOk && !dependentModIds.isEmpty() && !translationCatalogLoaded)
    {
        const QString translationCatalogQuery = QString::fromLatin1(R"GRAPHQL(
query AvailableTranslations(
  $filter: ModsFilter,
  $offset: Int!,
  $count: Int!
) {
  mods(
    filter: $filter,
    offset: $offset,
    count: $count,
    viewUserBlockedContent: false
  ) {
    totalCount
    nodes {
      modId
      uid
      name
      author
      version
      updatedAt
      status
    }
  }
}
)GRAPHQL");

        QJsonArray tagFacet;
        tagFacet.append(QStringLiteral("Translation"));
        QJsonObject facets;
        facets.insert(QStringLiteral("tag"), tagFacet);

        QJsonObject gameIdCondition;
        gameIdCondition.insert(QStringLiteral("op"), QStringLiteral("EQUALS"));
        gameIdCondition.insert(QStringLiteral("value"), morrowindGraphGameId);
        QJsonArray gameIdFilter;
        gameIdFilter.append(gameIdCondition);

        QJsonObject statusCondition;
        statusCondition.insert(QStringLiteral("op"), QStringLiteral("EQUALS"));
        statusCondition.insert(QStringLiteral("value"), QStringLiteral("published"));
        QJsonArray statusFilter;
        statusFilter.append(statusCondition);

        QJsonObject tagCondition;
        tagCondition.insert(QStringLiteral("op"), QStringLiteral("EQUALS"));
        tagCondition.insert(QStringLiteral("value"), QStringLiteral("Translation"));
        QJsonArray tagFilter;
        tagFilter.append(tagCondition);

        QJsonObject filter;
        filter.insert(QStringLiteral("gameId"), gameIdFilter);
        filter.insert(QStringLiteral("status"), statusFilter);
        filter.insert(QStringLiteral("tag"), tagFilter);

        QJsonArray fetchedCatalog;
        int catalogOffset = 0;

        while (translationsLookupOk)
        {
            QJsonObject variables;
            variables.insert(QStringLiteral("filter"), filter);
            variables.insert(QStringLiteral("offset"), catalogOffset);
            variables.insert(QStringLiteral("count"), nexusGraphPageSize);

            QJsonObject graphData;
            if (!postGraphQl(translationCatalogQuery, variables, graphData, translationsError,
                    &hourlyRemaining, &dailyRemaining))
            {
                translationsLookupOk = false;
                break;
            }

            const QJsonObject modsPage = graphData.value(QStringLiteral("mods")).toObject();
            const QJsonArray nodes = modsPage.value(QStringLiteral("nodes")).toArray();
            const int totalCount = modsPage.value(QStringLiteral("totalCount")).toInt();

            for (const QJsonValue& value : nodes)
                fetchedCatalog.append(value);

            catalogOffset += nodes.size();
            if (nodes.isEmpty() || catalogOffset >= totalCount)
                break;
        }

        if (translationsLookupOk)
        {
            translationCatalog = fetchedCatalog;
            translationCatalogLoaded = true;
        }
    }

    if (translationsLookupOk && !dependentModIds.isEmpty())
    {
        for (const QJsonValue& value : translationCatalog)
        {
            const QJsonObject translation = value.toObject();
            const qint64 translationModId
                = translation.value(QStringLiteral("modId")).toVariant().toLongLong();
            if (dependentModIds.contains(translationModId))
                translations.push_back(translation);
        }

        // A Translation-tagged mod can require the current base mod only as a
        // framework/dependency while actually translating a different add-on.
        // Example: a translation of "The Ashlanders" can also require Tamriel
        // Rebuilt and would otherwise appear as a TR translation.
        //
        // Resolve ambiguous candidates from their own Nexus requirements. With
        // more than one requirement, compare the translation title against the
        // names of its required mods and treat the longest matching mod name as
        // the translation target. This stays language-neutral: no PL/Polish/etc.
        if (!translations.isEmpty())
        {
            const QString candidateRequirementsQuery = QString::fromLatin1(R"GRAPHQL(
query TranslationCandidateRequirements(
  $uids: [ID!]!,
  $count: Int!
) {
  modsByUid(uids: $uids, count: $count) {
    nodes {
      modId
      modRequirements {
        nexusRequirements(offset: 0, count: 80) {
          totalCount
          nodes {
            modId
            modName
          }
        }
      }
    }
  }
}
)GRAPHQL");

            QHash<qint64, QJsonObject> candidateRequirementPages;

            for (int batchStart = 0;
                 translationsLookupOk
                     && batchStart < static_cast<int>(translations.size());
                 batchStart += nexusGraphPageSize)
            {
                const int batchEnd = std::min(
                    batchStart + nexusGraphPageSize,
                    static_cast<int>(translations.size()));

                QJsonArray candidateUids;
                for (int index = batchStart; index < batchEnd; ++index)
                {
                    const QString uid
                        = translations.at(index)
                              .value(QStringLiteral("uid"))
                              .toVariant().toString().trimmed();
                    if (!uid.isEmpty())
                        candidateUids.append(uid);
                }

                if (candidateUids.isEmpty())
                    continue;

                QJsonObject variables;
                variables.insert(QStringLiteral("uids"), candidateUids);
                variables.insert(QStringLiteral("count"), candidateUids.size());

                QJsonObject graphData;
                if (!postGraphQl(candidateRequirementsQuery, variables, graphData,
                        translationsError, &hourlyRemaining, &dailyRemaining))
                {
                    translationsLookupOk = false;
                    break;
                }

                const QJsonArray candidateNodes
                    = graphData.value(QStringLiteral("modsByUid")).toObject()
                          .value(QStringLiteral("nodes")).toArray();

                for (const QJsonValue& candidateValue : candidateNodes)
                {
                    const QJsonObject candidate = candidateValue.toObject();
                    const qint64 candidateModId
                        = candidate.value(QStringLiteral("modId"))
                              .toVariant().toLongLong();
                    if (candidateModId <= 0)
                        continue;

                    candidateRequirementPages.insert(
                        candidateModId,
                        candidate.value(QStringLiteral("modRequirements")).toObject()
                            .value(QStringLiteral("nexusRequirements")).toObject());
                }
            }

            const auto normalizeModName = [](const QString& value) -> QString
            {
                const QString folded = value.toCaseFolded();
                QString normalized;
                normalized.reserve(folded.size());

                for (const QChar character : folded)
                {
                    if (character.isLetterOrNumber())
                        normalized.append(character);
                }

                return normalized;
            };

            if (translationsLookupOk)
            {
                QVector<QJsonObject> directTranslations;

                for (const QJsonObject& translation : translations)
                {
                    const qint64 translationModId
                        = translation.value(QStringLiteral("modId"))
                              .toVariant().toLongLong();
                    const QJsonObject requirementPage
                        = candidateRequirementPages.value(translationModId);

                    // We know from modsRequiringThisMod that the base relation
                    // exists, so missing details here mean the candidate could not
                    // be classified reliably. Be conservative rather than show a
                    // possibly unrelated translation.
                    if (requirementPage.isEmpty())
                        continue;

                    const QJsonArray requirements
                        = requirementPage.value(QStringLiteral("nodes")).toArray();
                    const int totalRequirements
                        = requirementPage.value(QStringLiteral("totalCount")).toInt();

                    // The query asks for at most 80 requirements. Do not classify
                    // from incomplete data.
                    if (totalRequirements > requirements.size())
                        continue;

                    bool requiresBaseMod = false;
                    int validRequirementCount = 0;

                    for (const QJsonValue& requirementValue : requirements)
                    {
                        const qint64 requiredModId
                            = requirementValue.toObject()
                                  .value(QStringLiteral("modId"))
                                  .toVariant().toLongLong();
                        if (requiredModId <= 0)
                            continue;

                        ++validRequirementCount;
                        if (requiredModId == modId)
                            requiresBaseMod = true;
                    }

                    if (!requiresBaseMod)
                        continue;

                    // One Nexus requirement and it is our base mod: unambiguous.
                    if (validRequirementCount == 1)
                    {
                        directTranslations.push_back(translation);
                        continue;
                    }

                    const QString normalizedTranslationName
                        = normalizeModName(
                            translation.value(QStringLiteral("name")).toString());

                    qint64 bestMatchedTargetModId = 0;
                    int bestMatchedNameLength = 0;

                    for (const QJsonValue& requirementValue : requirements)
                    {
                        const QJsonObject requirement = requirementValue.toObject();
                        const qint64 requiredModId
                            = requirement.value(QStringLiteral("modId"))
                                  .toVariant().toLongLong();
                        const QString normalizedRequiredName
                            = normalizeModName(
                                requirement.value(QStringLiteral("modName")).toString());

                        if (requiredModId <= 0
                            || normalizedRequiredName.isEmpty()
                            || !normalizedTranslationName.contains(
                                normalizedRequiredName))
                        {
                            continue;
                        }

                        // Prefer the longest matched required-mod name. This makes
                        // "The Ashlanders - Polish Translation" resolve to
                        // The Ashlanders rather than to a framework it also needs.
                        if (normalizedRequiredName.size() > bestMatchedNameLength)
                        {
                            bestMatchedNameLength = normalizedRequiredName.size();
                            bestMatchedTargetModId = requiredModId;
                        }
                    }

                    if (bestMatchedTargetModId == modId)
                        directTranslations.push_back(translation);
                }

                translations = directTranslations;
            }
        }

        // Nexus Mod.version can lag behind the actual downloadable file version.
        // Resolve the displayed translation version from the file list instead:
        // 1) newest non-archived primary file,
        // 2) newest non-archived MAIN file,
        // 3) newest remaining non-archived file.
        //
        // Cache results for the launcher session so reopening mod details does not
        // repeat one REST request per detected translation.
        static QHash<qint64, QString> translationFileVersionCache;
        static QHash<qint64, qint64> translationFileIdCache;
        static QSet<qint64> translationFileVersionLookupComplete;

        for (QJsonObject& translation : translations)
        {
            const qint64 translationModId
                = translation.value(QStringLiteral("modId")).toVariant().toLongLong();
            if (translationModId <= 0)
                continue;

            if (!translationFileVersionLookupComplete.contains(translationModId))
            {
                QString resolvedVersion;
                qint64 resolvedFileId = 0;

                QJsonDocument translationFilesDocument;
                QString translationFilesError;
                const QUrl translationFilesUrl(
                    QStringLiteral(
                        "https://api.nexusmods.com/v1/games/morrowind/mods/%1/files.json")
                        .arg(translationModId));

                if (getJson(translationFilesUrl, translationFilesDocument,
                        translationFilesError, &hourlyRemaining, &dailyRemaining)
                    && translationFilesDocument.isObject())
                {
                    const QJsonArray translationFiles
                        = translationFilesDocument.object()
                              .value(QStringLiteral("files")).toArray();

                    QJsonObject newestPrimaryFile;
                    QJsonObject newestMainFile;
                    QJsonObject newestFallbackFile;
                    qint64 newestPrimaryTimestamp = -1;
                    qint64 newestMainTimestamp = -1;
                    qint64 newestFallbackTimestamp = -1;

                    for (const QJsonValue& fileValue : translationFiles)
                    {
                        const QJsonObject file = fileValue.toObject();
                        const QString category
                            = file.value(QStringLiteral("category_name"))
                                  .toString().trimmed();

                        if (category.compare(
                                QStringLiteral("ARCHIVED"), Qt::CaseInsensitive) == 0
                            || category.compare(
                                QStringLiteral("DELETED"), Qt::CaseInsensitive) == 0
                            || category.compare(
                                QStringLiteral("REMOVED"), Qt::CaseInsensitive) == 0)
                        {
                            continue;
                        }

                        const qint64 uploadedTimestamp
                            = file.value(QStringLiteral("uploaded_timestamp"))
                                  .toVariant().toLongLong();

                        if (file.value(QStringLiteral("is_primary")).toBool(false)
                            && uploadedTimestamp >= newestPrimaryTimestamp)
                        {
                            newestPrimaryTimestamp = uploadedTimestamp;
                            newestPrimaryFile = file;
                        }

                        if (category.compare(
                                QStringLiteral("MAIN"), Qt::CaseInsensitive) == 0
                            && uploadedTimestamp >= newestMainTimestamp)
                        {
                            newestMainTimestamp = uploadedTimestamp;
                            newestMainFile = file;
                        }

                        if (uploadedTimestamp >= newestFallbackTimestamp)
                        {
                            newestFallbackTimestamp = uploadedTimestamp;
                            newestFallbackFile = file;
                        }
                    }

                    QJsonObject selectedFile;
                    if (!newestPrimaryFile.isEmpty())
                        selectedFile = newestPrimaryFile;
                    else if (!newestMainFile.isEmpty())
                        selectedFile = newestMainFile;
                    else
                        selectedFile = newestFallbackFile;

                    resolvedFileId
                        = selectedFile.value(QStringLiteral("file_id"))
                              .toVariant().toLongLong();
                    resolvedVersion
                        = selectedFile.value(QStringLiteral("version"))
                              .toString().trimmed();

                    if (resolvedVersion.isEmpty())
                    {
                        resolvedVersion
                            = selectedFile.value(QStringLiteral("mod_version"))
                                  .toString().trimmed();
                    }
                }

                translationFileVersionCache.insert(
                    translationModId, resolvedVersion);
                translationFileIdCache.insert(
                    translationModId, resolvedFileId);
                translationFileVersionLookupComplete.insert(translationModId);
            }

            const QString resolvedVersion
                = translationFileVersionCache.value(translationModId).trimmed();
            const qint64 resolvedFileId
                = translationFileIdCache.value(translationModId, 0);
            if (!resolvedVersion.isEmpty())
            {
                translation.insert(
                    QStringLiteral("_resolvedFileVersion"), resolvedVersion);
            }
            if (resolvedFileId > 0)
            {
                translation.insert(
                    QStringLiteral("_resolvedFileId"),
                    QJsonValue::fromVariant(resolvedFileId));
            }
        }

        std::sort(translations.begin(), translations.end(),
            [](const QJsonObject& lhs, const QJsonObject& rhs) {
                return lhs.value(QStringLiteral("name")).toString().compare(
                           rhs.value(QStringLiteral("name")).toString(),
                           Qt::CaseInsensitive) < 0;
            });
    }

    const auto formatTimestamp = [](qint64 timestamp) -> QString
    {
        if (timestamp <= 0)
            return QStringLiteral("-");
        return QDateTime::fromSecsSinceEpoch(timestamp)
            .toLocalTime()
            .toString(QStringLiteral("yyyy-MM-dd HH:mm"));
    };

    QDialog dialog(this);
    dialog.setWindowTitle(tr("Nexus Mods - Mod Details"));
    dialog.resize(1000, 650);

    auto* layout = new QVBoxLayout(&dialog);

    QStringList infoLines;
    infoLines << tr("Name: %1").arg(mod.value(QStringLiteral("name")).toString(QStringLiteral("-")));
    infoLines << tr("Author: %1").arg(mod.value(QStringLiteral("author")).toString(QStringLiteral("-")));
    infoLines << tr("Version: %1").arg(mod.value(QStringLiteral("version")).toString(QStringLiteral("-")));
    infoLines << tr("Mod ID: %1").arg(modId);
    infoLines << tr("Status: %1").arg(mod.value(QStringLiteral("status")).toString(QStringLiteral("-")));
    infoLines << tr("Updated: %1").arg(
        formatTimestamp(mod.value(QStringLiteral("updated_timestamp")).toVariant().toLongLong()));

    const qint64 downloads = mod.value(QStringLiteral("mod_downloads")).toVariant().toLongLong();
    const qint64 uniqueDownloads = mod.value(QStringLiteral("mod_unique_downloads")).toVariant().toLongLong();
    if (downloads > 0 || uniqueDownloads > 0)
        infoLines << tr("Downloads: %1 (%2 unique)")
                         .arg(QLocale().toString(downloads))
                         .arg(QLocale().toString(uniqueDownloads));

    auto* infoLabel = new QLabel(infoLines.join('\n'), &dialog);
    infoLabel->setTextFormat(Qt::PlainText);
    infoLabel->setTextInteractionFlags(Qt::TextSelectableByMouse);
    layout->addWidget(infoLabel);

    const QString summary = mod.value(QStringLiteral("summary")).toString().trimmed();
    if (!summary.isEmpty())
    {
        auto* summaryLabel = new QLabel(tr("Summary: %1").arg(summary), &dialog);
        summaryLabel->setTextFormat(Qt::PlainText);
        summaryLabel->setWordWrap(true);
        summaryLabel->setTextInteractionFlags(Qt::TextSelectableByMouse);
        layout->addWidget(summaryLabel);
    }

    auto* filesLabel = new QLabel(tr("Files: %1").arg(files.size()), &dialog);
    layout->addWidget(filesLabel);

    auto* table = new QTableWidget(files.size(), 8, &dialog);
    table->setHorizontalHeaderLabels({
        tr("Use"),
        tr("Category"),
        tr("Name"),
        tr("Version"),
        tr("Archive"),
        tr("Size"),
        tr("Uploaded"),
        tr("File ID"),
    });
    table->setSelectionBehavior(QAbstractItemView::SelectRows);
    table->setSelectionMode(QAbstractItemView::NoSelection);
    table->setEditTriggers(QAbstractItemView::NoEditTriggers);
    table->setAlternatingRowColors(true);

    for (int row = 0; row < files.size(); ++row)
    {
        const QJsonObject file = files.at(row).toObject();

        const qint64 sizeKb = file.value(QStringLiteral("size_kb")).toVariant().toLongLong();
        QString sizeText = QStringLiteral("-");
        if (sizeKb > 0)
            sizeText = QLocale().formattedDataSize(sizeKb * 1024);

        const QString uploaded = formatTimestamp(
            file.value(QStringLiteral("uploaded_timestamp")).toVariant().toLongLong());

        auto* useItem = new QTableWidgetItem;
        useItem->setFlags(
            (useItem->flags() | Qt::ItemIsUserCheckable) & ~Qt::ItemIsEditable);
        useItem->setCheckState(Qt::Unchecked);
        useItem->setTextAlignment(Qt::AlignCenter);
        table->setItem(row, 0, useItem);

        const QStringList values{
            file.value(QStringLiteral("category_name")).toString(QStringLiteral("-")),
            file.value(QStringLiteral("name")).toString(QStringLiteral("-")),
            file.value(QStringLiteral("version")).toString(QStringLiteral("-")),
            file.value(QStringLiteral("file_name")).toString(QStringLiteral("-")),
            sizeText,
            uploaded,
            QString::number(file.value(QStringLiteral("file_id")).toVariant().toLongLong()),
        };

        for (int column = 0; column < values.size(); ++column)
            table->setItem(row, column + 1, new QTableWidgetItem(values.at(column)));
    }

    auto* header = table->horizontalHeader();
    header->setSectionResizeMode(0, QHeaderView::ResizeToContents);
    header->setSectionResizeMode(1, QHeaderView::ResizeToContents);
    header->setSectionResizeMode(2, QHeaderView::Stretch);
    header->setSectionResizeMode(3, QHeaderView::ResizeToContents);
    header->setSectionResizeMode(4, QHeaderView::Stretch);
    header->setSectionResizeMode(5, QHeaderView::ResizeToContents);
    header->setSectionResizeMode(6, QHeaderView::ResizeToContents);
    header->setSectionResizeMode(7, QHeaderView::ResizeToContents);

    layout->addWidget(table, 1);

    auto* translationsLabel = new QLabel(
        translationsLookupOk
            ? tr("Available translations: %1").arg(translations.size())
            : tr("Available translations: unavailable"),
        &dialog);
    if (!translationsLookupOk && !translationsError.isEmpty())
        translationsLabel->setToolTip(translationsError);
    layout->addWidget(translationsLabel);

    QTableWidget* translationsTable = nullptr;
    if (translationsLookupOk && !translations.isEmpty())
    {
        translationsTable
            = new QTableWidget(static_cast<int>(translations.size()), 6, &dialog);
        translationsTable->setHorizontalHeaderLabels({
            tr("Use"),
            tr("Name"),
            tr("Author"),
            tr("Version"),
            tr("Updated"),
            tr("Mod ID"),
        });
        translationsTable->setSelectionBehavior(QAbstractItemView::SelectRows);
        translationsTable->setSelectionMode(QAbstractItemView::NoSelection);
        translationsTable->setEditTriggers(QAbstractItemView::NoEditTriggers);
        translationsTable->setAlternatingRowColors(true);
        translationsTable->verticalHeader()->setVisible(false);

        const auto formatGraphTimestamp = [](const QString& timestamp) -> QString
        {
            if (timestamp.trimmed().isEmpty())
                return QStringLiteral("-");

            const QDateTime dateTime = QDateTime::fromString(timestamp, Qt::ISODate);
            if (!dateTime.isValid())
                return timestamp;

            return dateTime.toLocalTime().toString(QStringLiteral("yyyy-MM-dd HH:mm"));
        };

        for (int row = 0; row < static_cast<int>(translations.size()); ++row)
        {
            const QJsonObject translation = translations.at(row);
            auto* useItem = new QTableWidgetItem;
            useItem->setFlags(
                (useItem->flags() | Qt::ItemIsUserCheckable) & ~Qt::ItemIsEditable);
            useItem->setCheckState(Qt::Unchecked);
            useItem->setTextAlignment(Qt::AlignCenter);
            translationsTable->setItem(row, 0, useItem);

            const QStringList values{
                translation.value(QStringLiteral("name")).toString(QStringLiteral("-")),
                translation.value(QStringLiteral("author")).toString(QStringLiteral("-")),
                translation.value(QStringLiteral("_resolvedFileVersion"))
                    .toString(
                        translation.value(QStringLiteral("version"))
                            .toString(QStringLiteral("-"))),
                formatGraphTimestamp(
                    translation.value(QStringLiteral("updatedAt")).toString()),
                QString::number(
                    translation.value(QStringLiteral("modId")).toVariant().toLongLong()),
            };

            for (int column = 0; column < values.size(); ++column)
                translationsTable->setItem(
                    row, column + 1, new QTableWidgetItem(values.at(column)));
        }

        auto* translationsHeader = translationsTable->horizontalHeader();
        translationsHeader->setSectionResizeMode(0, QHeaderView::ResizeToContents);
        translationsHeader->setSectionResizeMode(1, QHeaderView::Stretch);
        translationsHeader->setSectionResizeMode(2, QHeaderView::ResizeToContents);
        translationsHeader->setSectionResizeMode(3, QHeaderView::ResizeToContents);
        translationsHeader->setSectionResizeMode(4, QHeaderView::ResizeToContents);
        translationsHeader->setSectionResizeMode(5, QHeaderView::ResizeToContents);

        const int visibleRows
            = std::min(static_cast<int>(translations.size()), 5);
        translationsTable->setMaximumHeight(
            translationsTable->horizontalHeader()->height()
            + visibleRows * translationsTable->verticalHeader()->defaultSectionSize()
            + 8);
        layout->addWidget(translationsTable);
    }

    const auto checkedPlanRow = [](const QTableWidget* planTable) -> int {
        if (!planTable)
            return -1;

        for (int row = 0; row < planTable->rowCount(); ++row)
        {
            const QTableWidgetItem* useItem = planTable->item(row, 0);
            if (useItem && useItem->checkState() == Qt::Checked)
                return row;
        }
        return -1;
    };

    const auto setupPlanTable = [&dialog](QTableWidget* planTable) {
        if (!planTable)
            return;

        connect(planTable, &QTableWidget::itemChanged, &dialog,
            [planTable](QTableWidgetItem* item) {
                if (!item || item->column() != 0
                    || item->checkState() != Qt::Checked)
                {
                    return;
                }

                QSignalBlocker blocker(planTable);
                for (int row = 0; row < planTable->rowCount(); ++row)
                {
                    QTableWidgetItem* other = planTable->item(row, 0);
                    if (other && other != item)
                        other->setCheckState(Qt::Unchecked);
                }
            });

        connect(planTable, &QTableWidget::cellClicked, &dialog,
            [planTable](int row, int column) {
                if (column == 0)
                    return;

                QTableWidgetItem* useItem = planTable->item(row, 0);
                if (!useItem)
                    return;

                useItem->setCheckState(
                    useItem->checkState() == Qt::Checked
                        ? Qt::Unchecked
                        : Qt::Checked);
            });
    };

    setupPlanTable(table);
    setupPlanTable(translationsTable);

    auto* installPlanLabel = new QLabel(&dialog);
    installPlanLabel->setWordWrap(true);
    installPlanLabel->setTextInteractionFlags(Qt::TextSelectableByMouse);
    layout->addWidget(installPlanLabel);

    const auto updateInstallPlan =
        [this, installPlanLabel, table, translationsTable, files, translations, mod,
            checkedPlanRow]() {
            const int mainRow = checkedPlanRow(table);
            const int translationRow = checkedPlanRow(translationsTable);

            if (mainRow < 0 && translationRow < 0)
            {
                installPlanLabel->setText(
                    tr("Installation plan: select a mod file and/or a translation."));
                return;
            }

            QString mainName;
            QString mainVersion;
            if (mainRow >= 0 && mainRow < files.size())
            {
                const QJsonObject file = files.at(mainRow).toObject();
                mainName = file.value(QStringLiteral("name")).toString().trimmed();
                mainVersion = file.value(QStringLiteral("version")).toString().trimmed();
                if (mainName.isEmpty())
                    mainName = file.value(QStringLiteral("file_name")).toString().trimmed();
                if (mainVersion.isEmpty())
                    mainVersion = mod.value(QStringLiteral("version")).toString().trimmed();
                if (mainName.isEmpty())
                    mainName = QStringLiteral("-");
                if (mainVersion.isEmpty())
                    mainVersion = QStringLiteral("-");
            }

            QString translationName;
            QString translationVersion;
            if (translationRow >= 0
                && translationRow < static_cast<int>(translations.size()))
            {
                const QJsonObject translation = translations.at(translationRow);
                translationName
                    = translation.value(QStringLiteral("name")).toString().trimmed();
                translationVersion
                    = translation.value(QStringLiteral("_resolvedFileVersion"))
                          .toString().trimmed();
                if (translationVersion.isEmpty())
                    translationVersion
                        = translation.value(QStringLiteral("version")).toString().trimmed();
                if (translationName.isEmpty())
                    translationName = QStringLiteral("-");
                if (translationVersion.isEmpty())
                    translationVersion = QStringLiteral("-");
            }

            if (mainRow >= 0 && translationRow >= 0)
            {
                installPlanLabel->setText(
                    tr("To download and install:\n"
                       "1. Mod: %1 [%2]\n"
                       "2. Translation: %3 [%4]\n\n"
                       "Installation order: base mod → translation.")
                        .arg(mainName, mainVersion, translationName, translationVersion));
            }
            else if (mainRow >= 0)
            {
                installPlanLabel->setText(
                    tr("To download and install:\n1. Mod: %1 [%2]")
                        .arg(mainName, mainVersion));
            }
            else
            {
                installPlanLabel->setText(
                    tr("To download and install:\n"
                       "1. Translation: %1 [%2]\n\n"
                       "The translation will be added to an already installed base mod.")
                        .arg(translationName, translationVersion));
            }
        };

    connect(table, &QTableWidget::itemChanged, &dialog,
        [updateInstallPlan](QTableWidgetItem* item) {
            if (item && item->column() == 0)
                updateInstallPlan();
        });
    if (translationsTable)
    {
        connect(translationsTable, &QTableWidget::itemChanged, &dialog,
            [updateInstallPlan](QTableWidgetItem* item) {
                if (item && item->column() == 0)
                    updateInstallPlan();
            });
    }
    updateInstallPlan();

    QStringList apiLimitParts;
    if (!hourlyRemaining.isEmpty())
        apiLimitParts << tr("hourly: %1").arg(QString::fromLatin1(hourlyRemaining));
    if (!dailyRemaining.isEmpty())
        apiLimitParts << tr("daily: %1").arg(QString::fromLatin1(dailyRemaining));

    if (!apiLimitParts.isEmpty())
    {
        auto* limitLabel = new QLabel(
            tr("API requests remaining - %1").arg(apiLimitParts.join(QStringLiteral(", "))), &dialog);
        layout->addWidget(limitLabel);
    }

    auto* buttons = new QDialogButtonBox(QDialogButtonBox::Close, &dialog);
    QPushButton* downloadButton
        = buttons->addButton(tr("Download / Install"), QDialogButtonBox::ActionRole);

    const auto updateDownloadButton
        = [downloadButton, table, translationsTable, checkedPlanRow]() {
            downloadButton->setEnabled(
                checkedPlanRow(table) >= 0
                || checkedPlanRow(translationsTable) >= 0);
        };

    connect(table, &QTableWidget::itemChanged, &dialog,
        [updateDownloadButton](QTableWidgetItem* item) {
            if (item && item->column() == 0)
                updateDownloadButton();
        });
    if (translationsTable)
    {
        connect(translationsTable, &QTableWidget::itemChanged, &dialog,
            [updateDownloadButton](QTableWidgetItem* item) {
                if (item && item->column() == 0)
                    updateDownloadButton();
            });
    }
    updateDownloadButton();

    connect(downloadButton, &QPushButton::clicked, &dialog,
        [this, &dialog, table, translationsTable, files, translations, mod, modId,
            checkedPlanRow]() {
            const int mainRow = checkedPlanRow(table);
            const int translationRow = checkedPlanRow(translationsTable);

            if (mainRow < 0 && translationRow < 0)
            {
                QMessageBox::warning(this, tr("Nexus Mods"),
                    tr("Select a mod file and/or a translation."));
                return;
            }

            const QString modsDirectory = mLauncherSettings.getModsDirectory();
            if (modsDirectory.isEmpty() || !QDir(modsDirectory).exists())
            {
                QMessageBox::warning(this, tr("Install Mod"),
                    tr("Select a valid Mods Directory before installing a mod from an archive."));
                return;
            }

            NexusModMetadata mainMetadata;
            if (mainRow >= 0)
            {
                if (mainRow >= files.size())
                    return;

                const QJsonObject file = files.at(mainRow).toObject();

                mainMetadata.mModId = modId;
                mainMetadata.mFileId
                    = file.value(QStringLiteral("file_id")).toVariant().toLongLong();
                mainMetadata.mVersion
                    = file.value(QStringLiteral("version")).toString().trimmed();
                if (mainMetadata.mVersion.isEmpty())
                    mainMetadata.mVersion
                        = mod.value(QStringLiteral("version")).toString().trimmed();
                mainMetadata.mAuthor
                    = mod.value(QStringLiteral("author")).toString().trimmed();
                mainMetadata.mUploadedBy
                    = file.value(QStringLiteral("uploaded_by")).toString().trimmed();
                mainMetadata.mNexusName
                    = mod.value(QStringLiteral("name")).toString().trimmed();
                mainMetadata.mNexusFileName
                    = file.value(QStringLiteral("name")).toString().trimmed();
                mainMetadata.mInstallationFile
                    = file.value(QStringLiteral("file_name")).toString().trimmed();
                mainMetadata.mFileSize
                    = file.value(QStringLiteral("size_kb")).toVariant().toLongLong() * 1024;
                mainMetadata.mDescription
                    = mod.value(QStringLiteral("summary")).toString().trimmed();
                mainMetadata.mCategoryId
                    = mod.value(QStringLiteral("category_id")).toInt();
                mainMetadata.mCategoryName
                    = mod.value(QStringLiteral("category_name")).toString().trimmed();
                mainMetadata.mFileCategory
                    = file.value(QStringLiteral("category_name")).toString().trimmed();

                if (mainMetadata.mFileId <= 0
                    || mainMetadata.mInstallationFile.isEmpty())
                {
                    QMessageBox::warning(this, tr("Nexus Mods"),
                        tr("The selected Nexus Mods file does not contain valid download information."));
                    return;
                }
            }

            qint64 translationModId = 0;
            qint64 translationFileId = 0;
            NexusModMetadata translationMetadata;

            if (translationRow >= 0)
            {
                if (translationRow >= static_cast<int>(translations.size()))
                    return;

                const QJsonObject translation = translations.at(translationRow);
                translationModId
                    = translation.value(QStringLiteral("modId")).toVariant().toLongLong();
                translationFileId
                    = translation.value(QStringLiteral("_resolvedFileId"))
                          .toVariant().toLongLong();

                if (translationModId <= 0 || translationFileId <= 0
                    || translationModId > std::numeric_limits<int>::max())
                {
                    QMessageBox::warning(this, tr("Nexus Mods"),
                        tr("The selected translation does not have a valid current Nexus file."));
                    return;
                }

                if (!fetchNexusFileMetadata(
                        static_cast<int>(translationModId),
                        translationFileId, translationMetadata))
                {
                    return;
                }

                translationMetadata.mIsOverlay = true;
                translationMetadata.mPackageType = QStringLiteral("translation");
                translationMetadata.mTargetModId = modId;
            }

            if (mainRow >= 0 && translationRow < 0)
            {
                dialog.accept();
                downloadNexusFile(mainMetadata);
                return;
            }

            if (mainRow < 0 && translationRow >= 0)
            {
                QStringList targetPaths;
                QStringList targetLabels;

                for (const QString& candidatePath : modsDirectoryChildren())
                {
                    const QString metadataPath
                        = QDir(candidatePath).filePath(QStringLiteral("openmw-meta.ini"));
                    if (!QFileInfo(metadataPath).isFile())
                        continue;

                    QSettings candidateMetadata(metadataPath, QSettings::IniFormat);
                    const QString gameName
                        = candidateMetadata.value(QStringLiteral("gamename"))
                              .toString().trimmed();
                    const qint64 candidateModId
                        = candidateMetadata.value(QStringLiteral("modid")).toLongLong();

                    if (gameName.compare(QStringLiteral("morrowind"), Qt::CaseInsensitive) != 0
                        || candidateModId != modId)
                    {
                        continue;
                    }

                    const QString version
                        = candidateMetadata.value(QStringLiteral("version"))
                              .toString().trimmed();
                    const QString folderName = QFileInfo(candidatePath).fileName();

                    targetPaths.push_back(candidatePath);
                    targetLabels.push_back(version.isEmpty()
                        ? folderName
                        : QStringLiteral("%1  [%2]").arg(folderName, version));
                }

                if (targetPaths.isEmpty())
                {
                    QMessageBox::information(this, tr("Translation Overlay"),
                        tr("Install the base mod with this launcher before installing its translation."));
                    return;
                }

                int targetIndex = 0;
                if (targetPaths.size() > 1)
                {
                    bool targetAccepted = false;
                    const QString selected = QInputDialog::getItem(
                        this, tr("Translation Overlay"),
                        tr("Select the installed base mod to translate:"),
                        targetLabels, 0, false, &targetAccepted);

                    if (!targetAccepted)
                        return;

                    targetIndex = targetLabels.indexOf(selected);
                    if (targetIndex < 0 || targetIndex >= targetPaths.size())
                        return;
                }

                const QString targetPath = targetPaths.at(targetIndex);
                const QString targetMetadataPath
                    = QDir(targetPath).filePath(QStringLiteral("openmw-meta.ini"));
                QSettings targetMetadata(targetMetadataPath, QSettings::IniFormat);

                const QString packageGroup
                    = QStringLiteral("Package.%1").arg(translationModId);
                if (targetMetadata.childGroups().contains(
                        packageGroup, Qt::CaseInsensitive))
                {
                    QMessageBox::information(this, tr("Translation Overlay"),
                        tr("This translation package is already installed in the selected base mod."));
                    return;
                }

                const QString baseVersion
                    = targetMetadata.value(QStringLiteral("version")).toString().trimmed();
                translationMetadata.mTargetVersion = baseVersion;

                if (!baseVersion.isEmpty() && !translationMetadata.mVersion.isEmpty()
                    && baseVersion.compare(
                           translationMetadata.mVersion, Qt::CaseInsensitive) != 0)
                {
                    const QMessageBox::StandardButton answer = QMessageBox::warning(
                        this, tr("Translation Version"),
                        tr("Installed base mod version: %1\n"
                           "Translation package version: %2\n\n"
                           "The version strings do not match. The translation may be outdated "
                           "or may use a different versioning scheme.\n\n"
                           "Install it anyway?")
                            .arg(baseVersion, translationMetadata.mVersion),
                        QMessageBox::Yes | QMessageBox::No, QMessageBox::No);

                    if (answer != QMessageBox::Yes)
                        return;
                }

                dialog.accept();
                downloadNexusFile(
                    translationMetadata, QString(), targetPath);
                return;
            }

            if (!mainMetadata.mVersion.isEmpty()
                && !translationMetadata.mVersion.isEmpty()
                && mainMetadata.mVersion.compare(
                       translationMetadata.mVersion, Qt::CaseInsensitive) != 0)
            {
                const QMessageBox::StandardButton answer = QMessageBox::warning(
                    this, tr("Translation Version"),
                    tr("Selected base mod version: %1\n"
                       "Translation package version: %2\n\n"
                       "The version strings do not match. The translation may be outdated "
                       "or may use a different versioning scheme.\n\n"
                       "Continue with this installation plan?")
                        .arg(mainMetadata.mVersion, translationMetadata.mVersion),
                    QMessageBox::Yes | QMessageBox::No, QMessageBox::No);

                if (answer != QMessageBox::Yes)
                    return;
            }

            if (!mNexusPremium && !ensureNxmHandlerForDownload())
                return;

            dialog.accept();

            QString baseNxmUrl;
            QString translationNxmUrl;

            if (!mNexusPremium)
            {
                const auto downloadPageFor = [](const NexusModMetadata& metadata) {
                    return QUrl(
                        QStringLiteral(
                            "https://www.nexusmods.com/morrowind/mods/%1"
                            "?tab=files&file_id=%2&nmm=1")
                            .arg(metadata.mModId)
                            .arg(metadata.mFileId));
                };

                mPendingNxmModId = mainMetadata.mModId;
                mPendingNxmFileId = mainMetadata.mFileId;
                mPendingNxmSecondModId = translationMetadata.mModId;
                mPendingNxmSecondFileId = translationMetadata.mFileId;
                mReceivedNxmUrl.clear();
                mReceivedNxmSecondUrl.clear();

                QDialog waitDialog(this);
                waitDialog.setWindowTitle(tr("Nexus Mods - Free Download (2 files)"));
                waitDialog.setModal(true);
                waitDialog.resize(620, 230);

                auto* waitLayout = new QVBoxLayout(&waitDialog);

                auto* waitLabel = new QLabel(
                    tr("Two Nexus Mods download tabs are open.\n\n"
                       "Choose Slow Download on both tabs. The order of clicks does not matter.\n\n"
                       "The launcher will start installation only after both NXM links are received "
                       "and will always install the base mod first, then the translation."),
                    &waitDialog);
                waitLabel->setWordWrap(true);
                waitLayout->addWidget(waitLabel);

                auto* statusLabel = new QLabel(&waitDialog);
                statusLabel->setAlignment(Qt::AlignCenter);
                waitLayout->addWidget(statusLabel);

                auto* waitButtons = new QDialogButtonBox(
                    QDialogButtonBox::Cancel, &waitDialog);
                connect(waitButtons, &QDialogButtonBox::rejected,
                    &waitDialog, &QDialog::reject);
                waitLayout->addWidget(waitButtons);

                QTimer statusTimer(&waitDialog);
                const auto updatePlanDownloadStatus = [this, statusLabel]() {
                    int received = 0;
                    if (!mReceivedNxmUrl.isEmpty())
                        ++received;
                    if (!mReceivedNxmSecondUrl.isEmpty())
                        ++received;
                    statusLabel->setText(
                        tr("Received download links: %1 / 2").arg(received));
                };
                connect(&statusTimer, &QTimer::timeout,
                    &waitDialog, updatePlanDownloadStatus);
                statusTimer.start(100);
                updatePlanDownloadStatus();

                mNxmWaitDialog = &waitDialog;

                // Open the translation first and the base mod second so most
                // browsers leave the base mod tab active. Link collection is
                // order-independent, so the user can still click either tab first.
                const bool translationTabOpened
                    = QDesktopServices::openUrl(downloadPageFor(translationMetadata));
                const bool baseTabOpened
                    = QDesktopServices::openUrl(downloadPageFor(mainMetadata));

                if (!translationTabOpened || !baseTabOpened)
                {
                    mNxmWaitDialog = nullptr;
                    mPendingNxmModId = 0;
                    mPendingNxmFileId = 0;
                    mPendingNxmSecondModId = 0;
                    mPendingNxmSecondFileId = 0;
                    mReceivedNxmUrl.clear();
                    mReceivedNxmSecondUrl.clear();

                    QMessageBox::warning(this, tr("Nexus Mods"),
                        tr("Could not open both Nexus Mods download tabs."));
                    return;
                }

                const int waitResult = waitDialog.exec();
                statusTimer.stop();
                mNxmWaitDialog = nullptr;

                baseNxmUrl = mReceivedNxmUrl;
                translationNxmUrl = mReceivedNxmSecondUrl;

                mPendingNxmModId = 0;
                mPendingNxmFileId = 0;
                mPendingNxmSecondModId = 0;
                mPendingNxmSecondFileId = 0;
                mReceivedNxmUrl.clear();
                mReceivedNxmSecondUrl.clear();

                if (waitResult != QDialog::Accepted
                    || baseNxmUrl.isEmpty()
                    || translationNxmUrl.isEmpty())
                {
                    return;
                }
            }

            QString installedBasePath;
            downloadNexusFile(
                mainMetadata, baseNxmUrl, QString(), &installedBasePath);

            if (installedBasePath.isEmpty())
            {
                QMessageBox::information(this, tr("Installation Plan"),
                    tr("The base mod installation did not complete. "
                       "The translation was not installed."));
                return;
            }

            const QString installedMetadataPath
                = QDir(installedBasePath).filePath(QStringLiteral("openmw-meta.ini"));
            QSettings installedBaseMetadata(
                installedMetadataPath, QSettings::IniFormat);
            translationMetadata.mTargetVersion
                = installedBaseMetadata.value(QStringLiteral("version"))
                      .toString().trimmed();

            downloadNexusFile(
                translationMetadata, translationNxmUrl, installedBasePath);
        });
    connect(buttons, &QDialogButtonBox::rejected, &dialog, &QDialog::reject);
    layout->addWidget(buttons);

    dialog.exec();
}

bool Launcher::DataFilesPage::fetchNexusFileMetadata(
    int modId, qint64 fileId, NexusModMetadata& metadata)
{
    if (mNexusApiKey.isEmpty() || modId <= 0 || fileId <= 0)
        return false;

    QNetworkAccessManager networkManager;

    auto getJson = [&](const QUrl& url, QJsonDocument& document, QString& errorText) -> bool
    {
        QNetworkRequest request(url);
        request.setRawHeader("apikey", mNexusApiKey.toUtf8());
        request.setRawHeader("Application-Name", QByteArrayLiteral("OpenMW-Runtime-Localization-Fork"));
        request.setRawHeader("Application-Version", QByteArrayLiteral("0.4-dev"));

        QNetworkReply* reply = networkManager.get(request);
        QEventLoop eventLoop;
        connect(reply, &QNetworkReply::finished, &eventLoop, &QEventLoop::quit);
        eventLoop.exec();

        const QByteArray responseData = reply->readAll();
        const int httpStatus = reply->attribute(QNetworkRequest::HttpStatusCodeAttribute).toInt();
        const QNetworkReply::NetworkError networkErrorCode = reply->error();
        const QString networkError = reply->errorString();
        reply->deleteLater();

        QJsonParseError parseError;
        document = QJsonDocument::fromJson(responseData, &parseError);

        if (networkErrorCode != QNetworkReply::NoError || httpStatus < 200 || httpStatus >= 300)
        {
            QString apiMessage;
            if (document.isObject())
                apiMessage = document.object().value(QStringLiteral("message")).toString();

            errorText = tr("HTTP status: %1\n%2")
                            .arg(httpStatus)
                            .arg(apiMessage.isEmpty() ? networkError : apiMessage);
            return false;
        }

        if (parseError.error != QJsonParseError::NoError)
        {
            errorText = tr("Nexus Mods returned an invalid JSON response.");
            return false;
        }

        return true;
    };

    QJsonDocument modDocument;
    QJsonDocument filesDocument;
    QString errorText;

    const QUrl modUrl(
        QStringLiteral("https://api.nexusmods.com/v1/games/morrowind/mods/%1.json")
            .arg(modId));
    if (!getJson(modUrl, modDocument, errorText) || !modDocument.isObject())
    {
        QMessageBox::critical(this, tr("Nexus Mods"),
            tr("Could not retrieve mod information.\n%1").arg(errorText));
        return false;
    }

    const QUrl filesUrl(
        QStringLiteral("https://api.nexusmods.com/v1/games/morrowind/mods/%1/files.json")
            .arg(modId));
    if (!getJson(filesUrl, filesDocument, errorText) || !filesDocument.isObject())
    {
        QMessageBox::critical(this, tr("Nexus Mods"),
            tr("Could not retrieve the mod file list.\n%1").arg(errorText));
        return false;
    }

    const QJsonObject mod = modDocument.object();
    const QJsonArray files = filesDocument.object().value(QStringLiteral("files")).toArray();

    QJsonObject selectedFile;
    for (const QJsonValue& value : files)
    {
        const QJsonObject file = value.toObject();
        if (file.value(QStringLiteral("file_id")).toVariant().toLongLong() == fileId)
        {
            selectedFile = file;
            break;
        }
    }

    if (selectedFile.isEmpty())
    {
        QMessageBox::warning(this, tr("Nexus Mods"),
            tr("The file requested by the browser was not found in this Nexus Mods mod."));
        return false;
    }

    metadata = NexusModMetadata{};
    metadata.mModId = modId;
    metadata.mFileId = fileId;
    metadata.mVersion = selectedFile.value(QStringLiteral("version")).toString().trimmed();
    if (metadata.mVersion.isEmpty())
        metadata.mVersion = mod.value(QStringLiteral("version")).toString().trimmed();
    metadata.mAuthor = mod.value(QStringLiteral("author")).toString().trimmed();
    metadata.mUploadedBy = selectedFile.value(QStringLiteral("uploaded_by")).toString().trimmed();
    metadata.mNexusName = mod.value(QStringLiteral("name")).toString().trimmed();
    metadata.mNexusFileName = selectedFile.value(QStringLiteral("name")).toString().trimmed();
    metadata.mInstallationFile
        = selectedFile.value(QStringLiteral("file_name")).toString().trimmed();
    metadata.mFileSize
        = selectedFile.value(QStringLiteral("size_kb")).toVariant().toLongLong() * 1024;
    metadata.mDescription = mod.value(QStringLiteral("summary")).toString().trimmed();
    metadata.mCategoryId = mod.value(QStringLiteral("category_id")).toInt();
    metadata.mCategoryName = mod.value(QStringLiteral("category_name")).toString().trimmed();
    metadata.mFileCategory
        = selectedFile.value(QStringLiteral("category_name")).toString().trimmed();

    if (metadata.mInstallationFile.isEmpty())
    {
        QMessageBox::warning(this, tr("Nexus Mods"),
            tr("The file requested by the browser does not contain valid download information."));
        return false;
    }

    return true;
}

void Launcher::DataFilesPage::handleNxmUrl(const QString& urlText)
{
    const QUrl nxmUrl(urlText.trimmed(), QUrl::StrictMode);
    const QRegularExpression pathExpression(
        QStringLiteral(R"(^/mods/(\d+)/files/(\d+)$)"),
        QRegularExpression::CaseInsensitiveOption);
    const QRegularExpressionMatch pathMatch = pathExpression.match(nxmUrl.path());

    bool modIdOk = false;
    bool fileIdOk = false;
    const qint64 parsedModId = pathMatch.hasMatch()
        ? pathMatch.captured(1).toLongLong(&modIdOk)
        : 0;
    const qint64 fileId = pathMatch.hasMatch()
        ? pathMatch.captured(2).toLongLong(&fileIdOk)
        : 0;

    if (!nxmUrl.isValid()
        || nxmUrl.scheme().compare(QStringLiteral("nxm"), Qt::CaseInsensitive) != 0
        || nxmUrl.host().compare(QStringLiteral("morrowind"), Qt::CaseInsensitive) != 0
        || !pathMatch.hasMatch() || !modIdOk || !fileIdOk
        || parsedModId <= 0 || parsedModId > std::numeric_limits<int>::max()
        || fileId <= 0)
    {
        QMessageBox::warning(this, tr("Nexus Mods - NXM Link"),
            tr("The received URL is not a valid Morrowind NXM link."));
        return;
    }

    const int modId = static_cast<int>(parsedModId);

    // Internal launcher flow: preserve the exact pending file handshake.
    // A combined installation plan may wait for two independent NXM links.
    if (mNxmWaitDialog && mPendingNxmModId > 0 && mPendingNxmFileId > 0)
    {
        const bool hasSecondExpected
            = mPendingNxmSecondModId > 0 && mPendingNxmSecondFileId > 0;
        const bool matchesPrimary
            = modId == mPendingNxmModId && fileId == mPendingNxmFileId;
        const bool matchesSecond
            = hasSecondExpected
            && modId == mPendingNxmSecondModId
            && fileId == mPendingNxmSecondFileId;

        if (!matchesPrimary && !matchesSecond)
        {
            QMessageBox::warning(this, tr("Nexus Mods"),
                tr("The received NXM link does not match any file in the current installation plan."));
            return;
        }

        const QUrlQuery query(nxmUrl);
        const QString nxmKey = query.queryItemValue(QStringLiteral("key"));
        const QString nxmExpires = query.queryItemValue(QStringLiteral("expires"));

        bool expiresOk = false;
        const qint64 expires = nxmExpires.toLongLong(&expiresOk);
        bool userIdOk = false;
        const qint64 linkUserId
            = query.queryItemValue(QStringLiteral("user_id")).toLongLong(&userIdOk);

        if (nxmKey.isEmpty() || !expiresOk || expires <= QDateTime::currentSecsSinceEpoch())
        {
            QMessageBox::warning(this, tr("Nexus Mods"),
                tr("The NXM download link is missing its authorization data or has expired."));
            return;
        }

        if (mNexusUserId > 0 && userIdOk && linkUserId != mNexusUserId)
        {
            QMessageBox::warning(this, tr("Nexus Mods"),
                tr("The NXM link was generated for a different Nexus Mods account."));
            return;
        }

        const QString receivedUrl = nxmUrl.toString(QUrl::FullyEncoded);
        if (matchesPrimary)
            mReceivedNxmUrl = receivedUrl;
        else
            mReceivedNxmSecondUrl = receivedUrl;

        if (!hasSecondExpected
            || (!mReceivedNxmUrl.isEmpty() && !mReceivedNxmSecondUrl.isEmpty()))
        {
            mNxmWaitDialog->accept();
        }
        return;
    }

    // External browser flow:
    // Nexus website -> Mod Manager Download -> nxm:// -> this launcher.
    if (!ensureNexusConnected())
        return;

    if (!mNexusPremium)
    {
        const QUrlQuery query(nxmUrl);
        const QString nxmKey = query.queryItemValue(QStringLiteral("key"));
        const QString nxmExpires = query.queryItemValue(QStringLiteral("expires"));

        bool expiresOk = false;
        const qint64 expires = nxmExpires.toLongLong(&expiresOk);
        bool userIdOk = false;
        const qint64 linkUserId
            = query.queryItemValue(QStringLiteral("user_id")).toLongLong(&userIdOk);

        if (nxmKey.isEmpty() || !expiresOk || expires <= QDateTime::currentSecsSinceEpoch())
        {
            QMessageBox::warning(this, tr("Nexus Mods"),
                tr("The NXM download link is missing its authorization data or has expired."));
            return;
        }

        if (mNexusUserId > 0 && userIdOk && linkUserId != mNexusUserId)
        {
            QMessageBox::warning(this, tr("Nexus Mods"),
                tr("The NXM link was generated for a different Nexus Mods account."));
            return;
        }
    }

    NexusModMetadata metadata;
    if (!fetchNexusFileMetadata(modId, fileId, metadata))
        return;

    downloadNexusFile(metadata, nxmUrl.toString(QUrl::FullyEncoded));
}

void Launcher::DataFilesPage::downloadNexusFile(
    const NexusModMetadata& metadata, const QString& receivedNxmUrl,
    const QString& overlayTargetPath, QString* installedPathOut)
{
    if (installedPathOut)
        installedPathOut->clear();

    const int modId = metadata.mModId;
    const qint64 fileId = metadata.mFileId;
    const QString& fileName = metadata.mInstallationFile;
    const QString& modName = metadata.mNexusName;

    if (mNexusApiKey.isEmpty())
    {
        QMessageBox::warning(this, tr("Nexus Mods"), tr("Connect to Nexus Mods first."));
        return;
    }

    QString nxmKey;
    QString nxmExpires;

    if (!mNexusPremium)
    {
        if (!receivedNxmUrl.isEmpty())
        {
            const QUrl nxmUrl(receivedNxmUrl, QUrl::StrictMode);
            const QString expectedPath
                = QStringLiteral("/mods/%1/files/%2").arg(modId).arg(fileId);

            if (!nxmUrl.isValid()
                || nxmUrl.scheme().compare(QStringLiteral("nxm"), Qt::CaseInsensitive) != 0
                || nxmUrl.host().compare(QStringLiteral("morrowind"), Qt::CaseInsensitive) != 0
                || nxmUrl.path().compare(expectedPath, Qt::CaseInsensitive) != 0)
            {
                QMessageBox::warning(this, tr("Nexus Mods"),
                    tr("The received NXM link does not match the selected Morrowind file."));
                return;
            }

            const QUrlQuery query(nxmUrl);
            nxmKey = query.queryItemValue(QStringLiteral("key"));
            nxmExpires = query.queryItemValue(QStringLiteral("expires"));

            bool expiresOk = false;
            const qint64 expires = nxmExpires.toLongLong(&expiresOk);
            bool userIdOk = false;
            const qint64 linkUserId
                = query.queryItemValue(QStringLiteral("user_id")).toLongLong(&userIdOk);

            if (nxmKey.isEmpty() || !expiresOk
                || expires <= QDateTime::currentSecsSinceEpoch())
            {
                QMessageBox::warning(this, tr("Nexus Mods"),
                    tr("The NXM download link is missing its authorization data or has expired."));
                return;
            }

            if (mNexusUserId > 0 && userIdOk && linkUserId != mNexusUserId)
            {
                QMessageBox::warning(this, tr("Nexus Mods"),
                    tr("The NXM link was generated for a different Nexus Mods account."));
                return;
            }
        }
        else
        {
            if (!ensureNxmHandlerForDownload())
                return;

            mPendingNxmModId = modId;
            mPendingNxmFileId = fileId;
            mReceivedNxmUrl.clear();

            QDialog waitDialog(this);
            waitDialog.setWindowTitle(tr("Nexus Mods - Free Download"));
            waitDialog.setModal(true);
            waitDialog.resize(560, 180);

            auto* waitLayout = new QVBoxLayout(&waitDialog);

            auto* waitLabel = new QLabel(
                tr("The Nexus Mods download page has been opened in your browser.\n\n"
                   "Choose Slow Download. "
                   "The launcher will receive the NXM link automatically."),
                &waitDialog);
            waitLabel->setWordWrap(true);
            waitLayout->addWidget(waitLabel);

            auto* statusLabel = new QLabel(tr("Waiting for the NXM download link..."), &waitDialog);
            statusLabel->setAlignment(Qt::AlignCenter);
            waitLayout->addWidget(statusLabel);

            auto* waitButtons = new QDialogButtonBox(QDialogButtonBox::Cancel, &waitDialog);
            connect(waitButtons, &QDialogButtonBox::rejected, &waitDialog, &QDialog::reject);
            waitLayout->addWidget(waitButtons);

            mNxmWaitDialog = &waitDialog;

            const QUrl downloadPage(
                QStringLiteral("https://www.nexusmods.com/morrowind/mods/%1?tab=files&file_id=%2&nmm=1")
                    .arg(modId)
                    .arg(fileId));

            if (!QDesktopServices::openUrl(downloadPage))
            {
                mNxmWaitDialog = nullptr;
                mPendingNxmModId = 0;
                mPendingNxmFileId = 0;
                mReceivedNxmUrl.clear();

                QMessageBox::warning(this, tr("Nexus Mods"),
                    tr("Could not open the Nexus Mods download page."));
                return;
            }

            const int waitResult = waitDialog.exec();

            mNxmWaitDialog = nullptr;
            mPendingNxmModId = 0;
            mPendingNxmFileId = 0;

            if (waitResult != QDialog::Accepted || mReceivedNxmUrl.isEmpty())
            {
                mReceivedNxmUrl.clear();
                return;
            }

            const QUrl nxmUrl(mReceivedNxmUrl, QUrl::StrictMode);
            mReceivedNxmUrl.clear();

            const QUrlQuery query(nxmUrl);
            nxmKey = query.queryItemValue(QStringLiteral("key"));
            nxmExpires = query.queryItemValue(QStringLiteral("expires"));
        }
    }

    QUrl apiUrl(QStringLiteral(
        "https://api.nexusmods.com/v1/games/morrowind/mods/%1/files/%2/download_link.json")
                    .arg(modId)
                    .arg(fileId));

    if (!mNexusPremium)
    {
        QUrlQuery query;
        query.addQueryItem(QStringLiteral("key"), nxmKey);
        query.addQueryItem(QStringLiteral("expires"), nxmExpires);
        apiUrl.setQuery(query);
    }

    QNetworkRequest apiRequest(apiUrl);
    apiRequest.setRawHeader("apikey", mNexusApiKey.toUtf8());
    apiRequest.setRawHeader("Application-Name", QByteArrayLiteral("OpenMW-Runtime-Localization-Fork"));
    apiRequest.setRawHeader("Application-Version", QByteArrayLiteral("0.4-dev"));

    QNetworkAccessManager networkManager;
    QNetworkReply* apiReply = networkManager.get(apiRequest);

    QEventLoop apiLoop;
    connect(apiReply, &QNetworkReply::finished, &apiLoop, &QEventLoop::quit);
    apiLoop.exec();

    const QByteArray apiData = apiReply->readAll();
    const int apiStatus = apiReply->attribute(QNetworkRequest::HttpStatusCodeAttribute).toInt();
    const QString apiNetworkError = apiReply->errorString();
    const QNetworkReply::NetworkError apiErrorCode = apiReply->error();
    apiReply->deleteLater();

    QJsonParseError parseError;
    const QJsonDocument downloadDocument = QJsonDocument::fromJson(apiData, &parseError);

    if (apiErrorCode != QNetworkReply::NoError || apiStatus < 200 || apiStatus >= 300)
    {
        QString message;
        if (downloadDocument.isObject())
            message = downloadDocument.object().value(QStringLiteral("message")).toString();
        if (message.isEmpty())
            message = apiNetworkError;

        QMessageBox::critical(this, tr("Nexus Mods"),
            tr("Could not obtain a download link.\nHTTP status: %1\n%2").arg(apiStatus).arg(message));
        return;
    }

    if (parseError.error != QJsonParseError::NoError || !downloadDocument.isArray()
        || downloadDocument.array().isEmpty())
    {
        QMessageBox::critical(this, tr("Nexus Mods"),
            tr("Nexus Mods returned an invalid download-link response."));
        return;
    }

    const QJsonObject downloadServer = downloadDocument.array().at(0).toObject();
    QString uri = downloadServer.value(QStringLiteral("URI")).toString();
    if (uri.isEmpty())
        uri = downloadServer.value(QStringLiteral("uri")).toString();

    const QUrl downloadUrl(uri);
    if (!downloadUrl.isValid() || downloadUrl.scheme().toLower() != QLatin1String("https"))
    {
        QMessageBox::critical(this, tr("Nexus Mods"),
            tr("Nexus Mods did not return a valid HTTPS download URL."));
        return;
    }

    const QString modsDirectory = mLauncherSettings.getModsDirectory();
    if (modsDirectory.isEmpty() || !QDir(modsDirectory).exists())
    {
        QMessageBox::warning(this, tr("Install Mod"),
            tr("Select a valid Mods Directory before installing a mod from an archive."));
        return;
    }

    const QString suffix = QFileInfo(fileName).suffix();
    const QString temporaryTemplate = QDir(modsDirectory).filePath(
        QStringLiteral(".openmw-nexus-XXXXXX%1")
            .arg(suffix.isEmpty() ? QString() : QStringLiteral(".") + suffix));

    QTemporaryFile temporaryArchive(temporaryTemplate);
    temporaryArchive.setAutoRemove(true);
    if (!temporaryArchive.open())
    {
        QMessageBox::critical(this, tr("Nexus Mods"),
            tr("Could not create a temporary file for the Nexus Mods download."));
        return;
    }

    QNetworkRequest downloadRequest(downloadUrl);
    downloadRequest.setAttribute(
        QNetworkRequest::RedirectPolicyAttribute, QNetworkRequest::NoLessSafeRedirectPolicy);

    QNetworkReply* downloadReply = networkManager.get(downloadRequest);

    QProgressDialog progress(tr("Downloading %1...").arg(fileName), tr("Cancel"), 0, 1000, this);
    progress.setWindowTitle(tr("Nexus Mods Download"));
    progress.setWindowModality(Qt::WindowModal);
    progress.setMinimumDuration(0);

    bool canceled = false;
    bool writeFailed = false;

    connect(&progress, &QProgressDialog::canceled, downloadReply, [&]() {
        canceled = true;
        downloadReply->abort();
    });

    connect(downloadReply, &QNetworkReply::readyRead, downloadReply, [&]() {
        const QByteArray chunk = downloadReply->readAll();
        if (!chunk.isEmpty() && temporaryArchive.write(chunk) != chunk.size())
        {
            writeFailed = true;
            downloadReply->abort();
        }
    });

    connect(downloadReply, &QNetworkReply::downloadProgress, &progress,
        [&](qint64 received, qint64 total) {
            if (total > 0)
            {
                const int value = static_cast<int>(
                    std::clamp<qint64>((received * 1000) / total, 0, 1000));
                progress.setValue(value);
                progress.setLabelText(
                    tr("Downloading %1... %2 / %3")
                        .arg(fileName)
                        .arg(QLocale().formattedDataSize(received))
                        .arg(QLocale().formattedDataSize(total)));
            }
            else
            {
                progress.setLabelText(
                    tr("Downloading %1... %2")
                        .arg(fileName)
                        .arg(QLocale().formattedDataSize(received)));
            }
        });

    QEventLoop downloadLoop;
    connect(downloadReply, &QNetworkReply::finished, &downloadLoop, &QEventLoop::quit);
    downloadLoop.exec();

    const QByteArray remainingData = downloadReply->readAll();
    if (!remainingData.isEmpty() && temporaryArchive.write(remainingData) != remainingData.size())
        writeFailed = true;

    const int downloadStatus
        = downloadReply->attribute(QNetworkRequest::HttpStatusCodeAttribute).toInt();
    const QString downloadError = downloadReply->errorString();
    const QNetworkReply::NetworkError downloadErrorCode = downloadReply->error();
    downloadReply->deleteLater();

    // Do not call close() here: QProgressDialog can treat closing as a cancel
    // action and emit canceled(), which would mark a completed download as canceled.
    progress.hide();
    temporaryArchive.flush();

    if (canceled)
    {
        QMessageBox::information(this, tr("Nexus Mods Download"), tr("Download canceled."));
        return;
    }

    if (writeFailed)
    {
        QMessageBox::critical(this, tr("Nexus Mods Download"),
            tr("Could not write the downloaded archive to disk."));
        return;
    }

    if (downloadErrorCode != QNetworkReply::NoError
        || downloadStatus < 200 || downloadStatus >= 300)
    {
        QMessageBox::critical(this, tr("Nexus Mods Download"),
            tr("Download failed.\nHTTP status: %1\n%2").arg(downloadStatus).arg(downloadError));
        return;
    }

    NexusModMetadata installedMetadata = metadata;
    installedMetadata.mFileSize = temporaryArchive.size();
    temporaryArchive.close();

    installModArchive(
        temporaryArchive.fileName(), modName, fileName,
        &installedMetadata, overlayTargetPath, installedPathOut);
}

void Launcher::DataFilesPage::chooseModsDirectory()
{
    const QString current = mLauncherSettings.getModsDirectory();
    QString selected = QFileDialog::getExistingDirectory(
        this, tr("Select Mods Directory"), current, QFileDialog::ShowDirsOnly | QFileDialog::Option::ReadOnly);

    if (selected.isEmpty())
        return;

    const QDir selectedDir(selected);
    selected = selectedDir.canonicalPath();
    if (selected.isEmpty())
        selected = selectedDir.absolutePath();
    selected = QDir::cleanPath(selected);

    if (samePath(selected, current))
        return;

    removeManagedModsDirectoryEntries(current);
    mLauncherSettings.setModsDirectory(selected);
    ui.modsDirectoryLineEdit->setText(selected);

    refreshDataFilesView();
    mMainDialog->writeSettings();
}

void Launcher::DataFilesPage::clearModsDirectory()
{
    const QString current = mLauncherSettings.getModsDirectory();
    if (current.isEmpty())
        return;

    removeManagedModsDirectoryEntries(current);
    mLauncherSettings.setModsDirectory({});
    ui.modsDirectoryLineEdit->clear();

    refreshDataFilesView();
    mMainDialog->writeSettings();
}

bool Launcher::DataFilesPage::loadSettings()
{
    ui.navMeshMaxSizeSpinBox->setValue(getMaxNavMeshDbFileSizeMiB());

    QStringList profiles = mLauncherSettings.getContentLists();
    QString currentProfile = mLauncherSettings.getCurrentContentListName();

    qDebug() << "The current profile is: " << currentProfile;

    for (const QString& item : profiles)
        addProfile(item, false);

    // Hack: also add the current profile
    if (!currentProfile.isEmpty())
        addProfile(currentProfile, true);

    auto language = mLauncherSettings.getLanguage();

    // Bidirectional language sync:
    // launcher -> game is handled in saveSettings()
    // game -> launcher is handled here by reflecting the current primary
    // preferred locale in the Morrowind Content Language selector.
    //
    // The secondary preferred locale is intentionally ignored here because
    // the launcher has no UI for it.
    const std::vector<std::string> preferredLocales = Settings::general().mPreferredLocales;
    if (!preferredLocales.empty())
    {
        std::string primaryLocale = preferredLocales.front();
        std::ranges::transform(primaryLocale, primaryLocale.begin(),
            [](unsigned char c) { return static_cast<char>(std::tolower(c)); });

        const std::size_t separator = primaryLocale.find_first_of("-_");
        if (separator != std::string::npos)
            primaryLocale.resize(separator);

        if (primaryLocale == "en")
            language = QStringLiteral("English");
        else if (primaryLocale == "fr")
            language = QStringLiteral("French");
        else if (primaryLocale == "de")
            language = QStringLiteral("German");
        else if (primaryLocale == "it")
            language = QStringLiteral("Italian");
        else if (primaryLocale == "pl")
            language = QStringLiteral("Polish");
        else if (primaryLocale == "ru")
            language = QStringLiteral("Russian");
        else if (primaryLocale == "es")
            language = QStringLiteral("Spanish");
    }

    for (int i = 0; i < mSelector->languageBox()->count(); ++i)
    {
        QString languageItem = mSelector->languageBox()->itemData(i).toString();
        if (language == languageItem)
        {
            mSelector->languageBox()->setCurrentIndex(i);
            break;
        }
    }

    return true;
}

void Launcher::DataFilesPage::populateFileViews(const QString& contentModelName)
{
    mSelector->clearFiles();
    ui.archiveListWidget->clear();
    ui.directoryListWidget->clear();

    QList<Config::SettingValue> directories = mGameSettings.getDataDirs();
    QStringList contentModelDirectories = mLauncherSettings.getDataDirectoryList(contentModelName);

    ui.modsDirectoryLineEdit->setText(mLauncherSettings.getModsDirectory());

    const QString modsRoot = mLauncherSettings.getModsDirectory();
    mSelector->setManagedModsDirectory(modsRoot);
    const QStringList automaticMods = modsDirectoryChildren();

    if (!modsRoot.isEmpty())
    {
        // If the selected profile has not stored data directories yet, start
        // from the current user data= list so selecting a Mods Directory does
        // not discard manually configured directories.
        if (contentModelDirectories.isEmpty())
        {
            for (const Config::SettingValue& dir : directories)
            {
                if (mGameSettings.isUserSetting(dir))
                    contentModelDirectories.push_back(dir.originalRepresentation);
            }
        }

        // Forget auto-managed direct children that were physically removed
        // from the Mods Directory.
        contentModelDirectories.erase(
            std::remove_if(contentModelDirectories.begin(), contentModelDirectories.end(),
                [&](const QString& path) {
                    return isDirectChildPath(path, modsRoot) && !QDir(path).exists();
                }),
            contentModelDirectories.end());

        // Preserve the user's saved priority. Newly copied mods are appended
        // at the end, giving them the highest data= priority until reordered.
        for (const QString& modPath : automaticMods)
        {
            const bool alreadyPresent = std::any_of(
                contentModelDirectories.cbegin(), contentModelDirectories.cend(),
                [&](const QString& existing) { return samePath(existing, modPath); });

            if (!alreadyPresent)
                contentModelDirectories.push_back(modPath);
        }
    }

    if (!contentModelDirectories.isEmpty())
    {
        directories.erase(std::remove_if(directories.begin(), directories.end(),
                              [&](const Config::SettingValue& dir) { return mGameSettings.isUserSetting(dir); }),
            directories.end());
        for (const auto& dir : contentModelDirectories)
            directories.push_back(mGameSettings.processPathSettingValue({ dir }));
    }

    mDataLocal = mGameSettings.getDataLocal();
    if (!mDataLocal.isEmpty())
        directories.insert(0, { mDataLocal });

    const auto& resourcesVfs = mGameSettings.getResourcesVfs();
    if (!resourcesVfs.isEmpty())
        directories.insert(0, { resourcesVfs });

    QIcon containsDataIcon(":/images/openmw-plugin.png");

    QProgressDialog progressBar("Adding data directories", {}, 0, static_cast<int>(directories.size()), this);
    progressBar.setWindowModality(Qt::WindowModal);

    std::unordered_set<QString> visitedDirectories;
    for (qsizetype i = 0; i < directories.size(); ++i)
    {
        progressBar.setValue(static_cast<int>(i));

        const Config::SettingValue& currentDir = directories.at(i);
        if (!visitedDirectories.insert(currentDir.value).second)
            continue;

        // add new achives files presents in current directory
        addArchivesFromDir(currentDir.value);

        QStringList tooltip;

        // add content files present in current directory
        mSelector->addFiles(currentDir.value, mNewDataDirs.contains(currentDir.value));

        const bool containsContentFiles = mSelector->containsDataFiles(currentDir.value);
        const bool containsAssetFiles = mSelector->containsAssetFiles(currentDir.value);

        // A user data= directory is a mod even when it has no ESP/ESM.
        // Represent asset-only mods in Data Files without creating a fake
        // content= entry.
        if (mGameSettings.isUserSetting(currentDir) && !containsContentFiles && containsAssetFiles)
            mSelector->addAssetDirectory(currentDir.value, mNewDataDirs.contains(currentDir.value));

        // add current directory to list
        ui.directoryListWidget->addItem(currentDir.originalRepresentation);
        auto row = ui.directoryListWidget->count() - 1;
        auto* item = ui.directoryListWidget->item(row);
        item->setData(Qt::UserRole, QVariant::fromValue(currentDir));

        if (currentDir.value != currentDir.originalRepresentation)
            tooltip << tr("Resolved as %1").arg(currentDir.value);

        // Display new content with custom formatting
        if (mNewDataDirs.contains(currentDir.value))
        {
            tooltip << tr("Will be added to the current profile");
            QFont font = item->font();
            font.setBold(true);
            font.setItalic(true);
            item->setFont(font);
        }

        // deactivate data-local and resources/vfs: they are always included
        // same for ones from non-user config files
        if (currentDir.value == mDataLocal || currentDir.value == resourcesVfs
            || !mGameSettings.isUserSetting(currentDir))
        {
            auto flags = item->flags();
            item->setFlags(flags & ~(Qt::ItemIsDragEnabled | Qt::ItemIsDropEnabled | Qt::ItemIsEnabled));
            if (currentDir.value == mDataLocal)
                tooltip << tr("This is the data-local directory and cannot be disabled");
            else if (currentDir.value == resourcesVfs)
                tooltip << tr("This directory is part of OpenMW and cannot be disabled");
            else
                tooltip << tr("This directory is enabled in an openmw.cfg other than the user one");
        }

        // Add a "data file" icon if the directory contains a content file
        if (containsContentFiles)
        {
            item->setIcon(containsDataIcon);

            tooltip << tr("Contains content file(s)");
        }
        else
        {
            // Pad to correct vertical alignment
            QPixmap pixmap(QSize(200, 200)); // Arbitrary big number, will be scaled down to widget size
            pixmap.fill(QColor(0, 0, 0, 0));
            auto emptyIcon = QIcon(pixmap);
            item->setIcon(emptyIcon);
        }
        item->setToolTip(tooltip.join('\n'));
    }
    progressBar.setValue(progressBar.maximum());
    mSelector->sortFiles();
    updateAssetConflictStats();

    QList<Config::SettingValue> selectedArchives = mGameSettings.getArchiveList();
    QStringList contentModelSelectedArchives = mLauncherSettings.getArchiveList(contentModelName);
    if (!contentModelSelectedArchives.isEmpty())
    {
        selectedArchives.erase(std::remove_if(selectedArchives.begin(), selectedArchives.end(),
                                   [&](const Config::SettingValue& dir) { return mGameSettings.isUserSetting(dir); }),
            selectedArchives.end());
        for (const auto& dir : contentModelSelectedArchives)
            selectedArchives.push_back({ dir });
    }

    // sort and tick BSA according to profile
    int row = 0;
    for (const auto& archive : selectedArchives)
    {
        const auto match = ui.archiveListWidget->findItems(archive.value, Qt::MatchFixedString);
        if (match.isEmpty())
            continue;
        const auto name = match[0]->text();
        const auto oldrow = ui.archiveListWidget->row(match[0]);
        // entries may be duplicated, e.g. if a content list predated a BSA being added to a non-user config file
        if (oldrow < row)
            continue;
        ui.archiveListWidget->takeItem(oldrow);
        ui.archiveListWidget->insertItem(row, name);
        ui.archiveListWidget->item(row)->setCheckState(Qt::Checked);
        ui.archiveListWidget->item(row)->setData(Qt::UserRole, QVariant::fromValue(archive));
        if (!mGameSettings.isUserSetting(archive))
        {
            auto flags = ui.archiveListWidget->item(row)->flags();
            ui.archiveListWidget->item(row)->setFlags(
                flags & ~(Qt::ItemIsDragEnabled | Qt::ItemIsDropEnabled | Qt::ItemIsEnabled));
            ui.archiveListWidget->item(row)->setToolTip(
                tr("This archive is enabled in an openmw.cfg other than the user one"));
        }
        row++;
    }

    QStringList nonUserContent;
    for (const auto& content : mGameSettings.getContentList())
    {
        if (!mGameSettings.isUserSetting(content))
            nonUserContent.push_back(content.value);
    }
    mSelector->setNonUserContent(nonUserContent);
    mSelector->setProfileContent(mLauncherSettings.getContentListFiles(contentModelName));

    QStringList groundcoverFiles;
    for (const auto& groundcover : mGameSettings.values(QStringLiteral("groundcover")))
        groundcoverFiles.push_back(groundcover.value);
    mSelector->setGroundcoverFiles(groundcoverFiles);
}

void Launcher::DataFilesPage::applyDataDirectoryOrder(const QStringList& paths)
{
    if (paths.size() < 2)
        return;

    // Normalize requested paths for reliable matching.
    QStringList normalizedOrder;
    normalizedOrder.reserve(paths.size());
    for (const QString& path : paths)
        normalizedOrder.push_back(QDir::cleanPath(QFileInfo(path).absoluteFilePath()));

    QList<QListWidgetItem*> allItems;
    allItems.reserve(ui.directoryListWidget->count());
    while (ui.directoryListWidget->count() > 0)
        allItems.push_back(ui.directoryListWidget->takeItem(0));

    QVector<int> directorySlots;
    QHash<QString, QListWidgetItem*> directoryItems;

    for (int i = 0; i < allItems.size(); ++i)
    {
        QListWidgetItem* item = allItems.at(i);
        const Config::SettingValue setting = qvariant_cast<Config::SettingValue>(item->data(Qt::UserRole));
        const QString normalizedPath = QDir::cleanPath(QFileInfo(setting.value).absoluteFilePath());

        if (normalizedOrder.contains(normalizedPath, Qt::CaseInsensitive))
        {
            directorySlots.push_back(i);
            directoryItems.insert(normalizedPath.toLower(), item);
        }
    }

    if (directorySlots.size() == normalizedOrder.size())
    {
        for (int i = 0; i < directorySlots.size(); ++i)
        {
            QListWidgetItem* item = directoryItems.value(normalizedOrder.at(i).toLower(), nullptr);
            if (item)
                allItems[directorySlots.at(i)] = item;
        }
    }

    for (QListWidgetItem* item : allItems)
        ui.directoryListWidget->addItem(item);
}

void Launcher::DataFilesPage::updateAssetConflictStats()
{
    QStringList directories;
    mAssetConflictDetails.clear();

    // Resolve the actual directory of the selected game file (normally the
    // original Morrowind "Data Files"). That directory may live in the user's
    // openmw.cfg and therefore count as a user setting, but it is not a mod
    // and must never participate in mod-vs-mod conflict statistics.
    QStringList profileContent = mLauncherSettings.getContentListFiles(ui.profilesComboBox->currentText());
    QString gameFilePath = mSelector->gameFilePath(profileContent);

    // Fallback for old/empty launcher profiles: use the currently configured
    // OpenMW content list.
    if (gameFilePath.isEmpty())
    {
        QStringList configuredContent;
        for (const auto& content : mGameSettings.getContentList())
            configuredContent.push_back(content.value);
        gameFilePath = mSelector->gameFilePath(configuredContent);
    }

    const QString gameDataDirectory = gameFilePath.isEmpty()
        ? QString()
        : normalizedAbsolutePath(QFileInfo(gameFilePath).absolutePath());

    // Only enabled user data= entries are mods controlled by this launcher
    // profile. Fixed OpenMW directories and the selected game's own data
    // directory are intentionally excluded, so "Conflicts" means mod-vs-mod.
    for (int row = 0; row < ui.directoryListWidget->count(); ++row)
    {
        const QListWidgetItem* item = ui.directoryListWidget->item(row);
        if (!item || !(item->flags() & Qt::ItemIsEnabled))
            continue;

        const Config::SettingValue setting = qvariant_cast<Config::SettingValue>(item->data(Qt::UserRole));
        if (!mGameSettings.isUserSetting(setting))
            continue;

        if (!gameDataDirectory.isEmpty()
            && samePath(setting.value, gameDataDirectory))
            continue;

        if (mSelector->containsAssetFiles(setting.value))
            directories.push_back(setting.value);
    }

    struct Stats
    {
        int conflicts = 0;
        int wins = 0;
        int losses = 0;
    };

    QVector<Stats> stats(directories.size());
    QHash<QString, QVector<int>> owners;

    for (int i = 0; i < directories.size(); ++i)
    {
        const QHash<QString, QString> files = looseAssetFiles(directories.at(i));
        for (auto fileIt = files.cbegin(); fileIt != files.cend(); ++fileIt)
            owners[fileIt.key()].push_back(i);
    }

    for (auto it = owners.cbegin(); it != owners.cend(); ++it)
    {
        const QVector<int>& fileOwners = it.value();
        if (fileOwners.size() < 2)
            continue;

        // OpenMW resolves duplicate loose files in favour of the later
        // (higher-priority) data= directory.
        const int winner = fileOwners.constLast();

        for (const int owner : fileOwners)
        {
            ++stats[owner].conflicts;
            if (owner == winner)
                ++stats[owner].wins;
            else
                ++stats[owner].losses;

            QStringList otherMods;
            QStringList otherModPaths;
            for (const int other : fileOwners)
            {
                if (other == owner)
                    continue;

                QString modName = QFileInfo(directories.at(other)).fileName();
                if (modName.isEmpty())
                    modName = directories.at(other);
                otherMods.push_back(modName);
                otherModPaths.push_back(directories.at(other));
            }

            QString winnerMod = QFileInfo(directories.at(winner)).fileName();
            if (winnerMod.isEmpty())
                winnerMod = directories.at(winner);

            const QString key = normalizedAbsolutePath(directories.at(owner));
            mAssetConflictDetails[key].push_back(
                AssetConflictDetail{ it.key(), otherMods, otherModPaths, winnerMod, owner == winner });
        }
    }

    for (auto detailsIt = mAssetConflictDetails.begin(); detailsIt != mAssetConflictDetails.end(); ++detailsIt)
    {
        auto& details = detailsIt.value();
        std::sort(details.begin(), details.end(),
            [](const AssetConflictDetail& lhs, const AssetConflictDetail& rhs) {
                return lhs.mRelativePath.compare(rhs.mRelativePath, Qt::CaseInsensitive) < 0;
            });
    }

    mSelector->clearConflictStats();
    for (int i = 0; i < directories.size(); ++i)
    {
        mSelector->setDirectoryConflictStats(
            directories.at(i), stats[i].conflicts, stats[i].wins, stats[i].losses);
    }
}

void Launcher::DataFilesPage::showNexusModPage(const QString& path)
{
    const QDir modDirectory(path);
    QString metadataPath = modDirectory.filePath(QStringLiteral("openmw-meta.ini"));

    if (!QFileInfo::exists(metadataPath))
        metadataPath = modDirectory.filePath(QStringLiteral("meta.ini"));

    if (!QFileInfo(metadataPath).isFile())
        return;

    QSettings metadata(metadataPath, QSettings::IniFormat);

    // QSettings exposes a literal [General] section as root-level keys.
    const QString gameName = metadata.value(QStringLiteral("gamename")).toString().trimmed();
    const qint64 modId = metadata.value(QStringLiteral("modid")).toLongLong();
    const QString storedUrl = metadata.value(QStringLiteral("nexusurl")).toString().trimmed();

    QUrl nexusUrl;

    // Prefer the structured identifiers. This also avoids opening an arbitrary
    // URL if a mod ships a malicious or malformed metadata file.
    if (gameName.compare(QStringLiteral("morrowind"), Qt::CaseInsensitive) == 0 && modId > 0)
    {
        nexusUrl = QUrl(
            QStringLiteral("https://www.nexusmods.com/morrowind/mods/%1").arg(modId));
    }
    else
    {
        const QUrl candidate(storedUrl);
        const QRegularExpression nexusPath(
            QStringLiteral(R"(^/morrowind/mods/\d+/?$)"),
            QRegularExpression::CaseInsensitiveOption);

        const bool trustedHost
            = candidate.host().compare(QStringLiteral("www.nexusmods.com"), Qt::CaseInsensitive) == 0
            || candidate.host().compare(QStringLiteral("nexusmods.com"), Qt::CaseInsensitive) == 0;

        if (candidate.isValid()
            && candidate.scheme().compare(QStringLiteral("https"), Qt::CaseInsensitive) == 0
            && trustedHost
            && nexusPath.match(candidate.path()).hasMatch())
        {
            nexusUrl = candidate;
        }
    }

    if (!nexusUrl.isValid() || nexusUrl.isEmpty())
    {
        QMessageBox::warning(this, tr("Nexus Mods Metadata"),
            tr("Could not read a valid Nexus Mods page from this mod's metadata."));
        return;
    }

    if (!QDesktopServices::openUrl(nexusUrl))
    {
        QMessageBox::warning(this, tr("Nexus Mods Metadata"),
            tr("Could not open the Nexus Mods page."));
    }
}

void Launcher::DataFilesPage::deleteManagedMod(const QString& path)
{
    const QString modsRoot = mLauncherSettings.getModsDirectory();
    if (modsRoot.isEmpty() || !QDir(modsRoot).exists())
        return;

    const QString normalizedRoot = normalizedAbsolutePath(modsRoot);
    const QString normalizedPath = normalizedAbsolutePath(path);

    // Defense in depth: ContentSelector already resolves the row to a direct
    // child of Mods Directory, but never trust a destructive request without
    // validating it again here.
    if (!isDirectChildPath(normalizedPath, normalizedRoot))
    {
        QMessageBox::warning(this, tr("Delete Mod"),
            tr("Only mods stored directly inside the configured Mods Directory can be deleted here."));
        return;
    }

    const QFileInfo modInfo(normalizedPath);
    if (!modInfo.exists() || !modInfo.isDir() || modInfo.isSymLink())
    {
        QMessageBox::warning(this, tr("Delete Mod"),
            tr("The selected mod directory cannot be deleted safely."));
        return;
    }

    QMessageBox confirmation(QMessageBox::Warning, tr("Delete Mod"),
        tr("Delete mod \"%1\"?\n\n%2\n\nThis will permanently delete the entire mod directory from disk.")
            .arg(modInfo.fileName(), normalizedPath),
        QMessageBox::NoButton, this);

    QPushButton* deleteButton = confirmation.addButton(tr("Delete"), QMessageBox::DestructiveRole);
    QPushButton* cancelButton = confirmation.addButton(QMessageBox::Cancel);
    confirmation.setDefaultButton(cancelButton);
    confirmation.exec();

    if (confirmation.clickedButton() != deleteButton)
        return;

    // Groundcover entries are intentionally preserved across temporary scan
    // failures elsewhere in the launcher. An explicit uninstall is different:
    // remove groundcover assignments belonging to this mod before refreshing.
    QSet<QString> removedContentNames;
    QDirIterator contentIt(normalizedPath, QDir::Files | QDir::NoDotAndDotDot, QDirIterator::Subdirectories);
    while (contentIt.hasNext())
    {
        const QFileInfo fileInfo(contentIt.next());
        const QString suffix = fileInfo.suffix().toLower();
        if (suffix == QLatin1String("esm")
            || suffix == QLatin1String("esp")
            || suffix == QLatin1String("omwaddon")
            || suffix == QLatin1String("omwgame")
            || suffix == QLatin1String("omwscripts"))
        {
            removedContentNames.insert(fileInfo.fileName().toLower());
        }
    }

    QStringList remainingGroundcover;
    for (const QString& fileName : mSelector->groundcoverFiles())
    {
        if (!removedContentNames.contains(fileName.toLower()))
            remainingGroundcover.push_back(fileName);
    }

    if (!QDir(normalizedPath).removeRecursively())
    {
        QMessageBox::critical(this, tr("Delete Mod"),
            tr("Could not delete the mod directory:\n%1").arg(normalizedPath));
        return;
    }

    mGameSettings.remove(QStringLiteral("groundcover"));
    for (const QString& fileName : remainingGroundcover)
        mGameSettings.setMultiValue(QStringLiteral("groundcover"), { fileName });

    refreshDataFilesView();
    mMainDialog->writeSettings();
}

void Launcher::DataFilesPage::showAssetConflictDetails(const QString& path)
{
    const QString key = normalizedAbsolutePath(path);
    const auto it = mAssetConflictDetails.constFind(key);

    if (it == mAssetConflictDetails.cend() || it.value().isEmpty())
    {
        QMessageBox::information(this, tr("Asset Conflicts"),
            tr("No asset conflicts were found for this mod."));
        return;
    }

    const QVector<AssetConflictDetail>& details = it.value();

    int wins = 0;
    int losses = 0;
    for (const AssetConflictDetail& detail : details)
    {
        if (detail.mWins)
            ++wins;
        else
            ++losses;
    }

    QString modName = QFileInfo(path).fileName();
    if (modName.isEmpty())
        modName = path;

    QDialog dialog(this);
    dialog.setWindowTitle(tr("Asset Conflicts — %1").arg(modName));
    dialog.resize(960, 620);

    auto* layout = new QVBoxLayout(&dialog);

    auto* summary = new QLabel(
        tr("Conflicts: %1    Wins: %2    Loses: %3")
            .arg(details.size())
            .arg(wins)
            .arg(losses),
        &dialog);
    layout->addWidget(summary);

    auto* resolutionTitle = new QLabel(tr("Texture resolution comparison against %1:").arg(modName), &dialog);
    layout->addWidget(resolutionTitle);

    auto* resolutionTable = new QTableWidget(&dialog);
    resolutionTable->setColumnCount(6);
    resolutionTable->setHorizontalHeaderLabels(
        { tr("No."), tr("Mod"), tr("Higher"), tr("Lower"), tr("Equal"), tr("Suggestion") });
    resolutionTable->setEditTriggers(QAbstractItemView::NoEditTriggers);
    resolutionTable->setSelectionBehavior(QAbstractItemView::SelectRows);
    resolutionTable->setSelectionMode(QAbstractItemView::SingleSelection);
    resolutionTable->setAlternatingRowColors(true);
    resolutionTable->verticalHeader()->setVisible(false);
    // Height is calculated after rows are populated so this compact
    // summary does not consume unnecessary vertical space.
    layout->addWidget(resolutionTable);

    auto* resolutionNote = new QLabel(
        tr("Higher resolution does not always mean higher image quality. This is only a suggestion; load order is never changed automatically."),
        &dialog);
    resolutionNote->setWordWrap(true);
    layout->addWidget(resolutionNote);

    auto* filter = new QLineEdit(&dialog);
    filter->setPlaceholderText(tr("Filter conflicts..."));
    layout->addWidget(filter);

    auto* table = new QTableWidget(details.size(), 5, &dialog);
    table->setHorizontalHeaderLabels(
        { tr("File"), tr("Result"), tr("Winner"), tr("Resolution"), tr("Conflicts With") });
    table->setEditTriggers(QAbstractItemView::NoEditTriggers);
    table->setSelectionBehavior(QAbstractItemView::SelectRows);
    table->setSelectionMode(QAbstractItemView::SingleSelection);
    table->setAlternatingRowColors(true);
    table->setSortingEnabled(false);

    struct ResolutionComparison
    {
        QString mModName;
        int mHigher = 0;
        int mLower = 0;
        int mEqual = 0;
    };

    QHash<QString, QHash<QString, QString>> looseFilesByDirectory;
    auto filesForDirectory = [&](const QString& directory) -> const QHash<QString, QString>& {
        const QString directoryKey = normalizedAbsolutePath(directory);
        auto filesIt = looseFilesByDirectory.find(directoryKey);
        if (filesIt == looseFilesByDirectory.end())
            filesIt = looseFilesByDirectory.insert(directoryKey, looseAssetFiles(directory));
        return filesIt.value();
    };

    auto textureSizeFor = [&](const QString& directory, const QString& relativePath) -> QSize {
        const QHash<QString, QString>& files = filesForDirectory(directory);
        const auto fileIt = files.constFind(relativePath.toLower());
        if (fileIt == files.cend())
            return {};

        return readTextureSize(fileIt.value());
    };

    QHash<QString, ResolutionComparison> comparisons;

    for (int row = 0; row < details.size(); ++row)
    {
        const AssetConflictDetail& detail = details.at(row);

        auto* fileItem = new QTableWidgetItem(detail.mRelativePath);
        auto* resultItem = new QTableWidgetItem(detail.mWins ? tr("Wins") : tr("Loses"));
        auto* winnerItem = new QTableWidgetItem(detail.mWins ? tr("This mod") : detail.mWinnerMod);
        auto* resolutionItem = new QTableWidgetItem();
        auto* modsItem = new QTableWidgetItem(detail.mOtherMods.join(", "));

        fileItem->setToolTip(detail.mRelativePath);
        winnerItem->setToolTip(detail.mWinnerMod);
        modsItem->setToolTip(detail.mOtherMods.join("\n"));

        const QSize currentSize = textureSizeFor(path, detail.mRelativePath);
        if (currentSize.isValid() && !currentSize.isEmpty())
        {
            resolutionItem->setText(textureSizeText(currentSize));

            QStringList resolutionTooltip;
            resolutionTooltip.push_back(
                QStringLiteral("%1: %2").arg(modName, textureSizeText(currentSize)));

            const qint64 currentPixels
                = static_cast<qint64>(currentSize.width()) * static_cast<qint64>(currentSize.height());

            const int competitorCount = std::min(detail.mOtherMods.size(), detail.mOtherModPaths.size());
            for (int competitor = 0; competitor < competitorCount; ++competitor)
            {
                const QString& otherName = detail.mOtherMods.at(competitor);
                const QString& otherPath = detail.mOtherModPaths.at(competitor);
                const QSize otherSize = textureSizeFor(otherPath, detail.mRelativePath);
                if (!otherSize.isValid() || otherSize.isEmpty())
                    continue;

                resolutionTooltip.push_back(
                    QStringLiteral("%1: %2").arg(otherName, textureSizeText(otherSize)));

                const qint64 otherPixels
                    = static_cast<qint64>(otherSize.width()) * static_cast<qint64>(otherSize.height());

                const QString comparisonKey = normalizedAbsolutePath(otherPath);
                ResolutionComparison& comparison = comparisons[comparisonKey];
                comparison.mModName = otherName;

                if (otherPixels > currentPixels)
                    ++comparison.mHigher;
                else if (otherPixels < currentPixels)
                    ++comparison.mLower;
                else
                    ++comparison.mEqual;
            }

            resolutionItem->setToolTip(resolutionTooltip.join("\n"));
        }

        table->setItem(row, 0, fileItem);
        table->setItem(row, 1, resultItem);
        table->setItem(row, 2, winnerItem);
        table->setItem(row, 3, resolutionItem);
        table->setItem(row, 4, modsItem);
    }

    QStringList comparisonKeys = comparisons.keys();
    std::sort(comparisonKeys.begin(), comparisonKeys.end(),
        [&](const QString& lhs, const QString& rhs) {
            return comparisons.value(lhs).mModName.compare(
                       comparisons.value(rhs).mModName, Qt::CaseInsensitive)
                < 0;
        });

    resolutionTable->setRowCount(comparisonKeys.size());

    for (int row = 0; row < comparisonKeys.size(); ++row)
    {
        const ResolutionComparison& comparison = comparisons.value(comparisonKeys.at(row));

        QString suggestion;
        if (comparison.mHigher > comparison.mLower)
            suggestion = tr("Higher priority");
        else if (comparison.mLower > comparison.mHigher)
            suggestion = tr("Lower priority");
        else
            suggestion = tr("No clear suggestion");

        resolutionTable->setItem(row, 0, new QTableWidgetItem(QString::number(row + 1)));
        resolutionTable->setItem(row, 1, new QTableWidgetItem(comparison.mModName));
        resolutionTable->setItem(row, 2, new QTableWidgetItem(QString::number(comparison.mHigher)));
        resolutionTable->setItem(row, 3, new QTableWidgetItem(QString::number(comparison.mLower)));
        resolutionTable->setItem(row, 4, new QTableWidgetItem(QString::number(comparison.mEqual)));
        resolutionTable->setItem(row, 5, new QTableWidgetItem(suggestion));
    }

    if (comparisonKeys.isEmpty())
    {
        resolutionTable->setRowCount(1);
        auto* noDataItem = new QTableWidgetItem(tr("No comparable texture resolutions were found."));
        resolutionTable->setSpan(0, 0, 1, 6);
        resolutionTable->setItem(0, 0, noDataItem);
    }

    auto* resolutionHeader = resolutionTable->horizontalHeader();
    resolutionHeader->setSectionResizeMode(0, QHeaderView::ResizeToContents);
    resolutionHeader->setSectionResizeMode(1, QHeaderView::Stretch);
    resolutionHeader->setSectionResizeMode(2, QHeaderView::ResizeToContents);
    resolutionHeader->setSectionResizeMode(3, QHeaderView::ResizeToContents);
    resolutionHeader->setSectionResizeMode(4, QHeaderView::ResizeToContents);
    resolutionHeader->setSectionResizeMode(5, QHeaderView::ResizeToContents);
    // Use the same compact row height as the detailed conflict table below.
    // resizeRowsToContents() made the summary rows noticeably too tall.
    const int compactRowHeight = table->rowCount() > 0
        ? table->rowHeight(0)
        : table->verticalHeader()->defaultSectionSize();

    auto* resolutionVerticalHeader = resolutionTable->verticalHeader();
    resolutionVerticalHeader->setSectionResizeMode(QHeaderView::Fixed);
    resolutionVerticalHeader->setDefaultSectionSize(compactRowHeight);
    resolutionVerticalHeader->setMinimumSectionSize(compactRowHeight);

    // Keep the summary compact vertically as well. Show at most six rows;
    // additional competitors remain accessible with a scrollbar.
    const int visibleResolutionRows = std::min(resolutionTable->rowCount(), 6);
    int resolutionTableHeight
        = resolutionTable->horizontalHeader()->height() + 2 * resolutionTable->frameWidth() + 2;
    resolutionTableHeight += visibleResolutionRows * compactRowHeight;

    resolutionTable->setFixedHeight(resolutionTableHeight);
    resolutionTable->setVerticalScrollBarPolicy(
        resolutionTable->rowCount() > visibleResolutionRows ? Qt::ScrollBarAlwaysOn : Qt::ScrollBarAlwaysOff);

    auto* header = table->horizontalHeader();
    header->setSectionResizeMode(0, QHeaderView::Stretch);
    header->setSectionResizeMode(1, QHeaderView::ResizeToContents);
    header->setSectionResizeMode(2, QHeaderView::ResizeToContents);
    header->setSectionResizeMode(3, QHeaderView::ResizeToContents);
    header->setSectionResizeMode(4, QHeaderView::Stretch);

    table->setSortingEnabled(true);
    layout->addWidget(table);

    connect(filter, &QLineEdit::textChanged, &dialog, [table](const QString& text) {
        const QString needle = text.trimmed();

        for (int row = 0; row < table->rowCount(); ++row)
        {
            bool match = needle.isEmpty();
            if (!match)
            {
                for (int column = 0; column < table->columnCount(); ++column)
                {
                    const QTableWidgetItem* item = table->item(row, column);
                    if (item && item->text().contains(needle, Qt::CaseInsensitive))
                    {
                        match = true;
                        break;
                    }
                }
            }

            table->setRowHidden(row, !match);
        }
    });

    auto* buttons = new QDialogButtonBox(QDialogButtonBox::Close, &dialog);
    connect(buttons, &QDialogButtonBox::rejected, &dialog, &QDialog::reject);
    layout->addWidget(buttons);

    dialog.exec();
}

void Launcher::DataFilesPage::saveSettings(const QString& profile)
{
    Settings::navigator().mMaxNavmeshdbFileSize.set(
        static_cast<std::uint64_t>(std::max(0, ui.navMeshMaxSizeSpinBox->value())) * 1024 * 1024);

    QString profileName = profile;

    if (profileName.isEmpty())
        profileName = ui.profilesComboBox->currentText();

    // retrieve the data paths
    auto dirList = selectedDirectoriesPaths();

    // retrieve the files selected for the profile
    ContentSelectorModel::ContentFileList items = mSelector->selectedFiles();

    // set the value of the current profile (not necessarily the profile being saved!)
    mLauncherSettings.setCurrentContentListName(ui.profilesComboBox->currentText());

    QStringList fileNames;
    for (const ContentSelectorModel::EsmFile* item : items)
    {
        fileNames.append(item->fileName());
    }
    QStringList dirNames;
    for (const auto& dir : dirList)
    {
        if (mGameSettings.isUserSetting(dir))
            dirNames.push_back(dir.originalRepresentation);
    }
    QStringList archiveNames;
    for (const auto& archive : selectedArchivePaths())
    {
        if (mGameSettings.isUserSetting(archive))
            archiveNames.push_back(archive.originalRepresentation);
    }
    mLauncherSettings.setContentList(profileName, dirNames, archiveNames, fileNames);
    mGameSettings.setContentList(dirList, selectedArchivePaths(), fileNames);

    // Groundcover uses its own ordered groundcover= entries in openmw.cfg
    // and must stay separate from the normal content= load order.
    mGameSettings.remove(QStringLiteral("groundcover"));
    const QStringList groundcoverFiles = mSelector->groundcoverFiles();
    for (const QString& fileName : groundcoverFiles)
        mGameSettings.setMultiValue(QStringLiteral("groundcover"), { fileName });

    QString language(mSelector->languageBox()->currentData().toString());

    mLauncherSettings.setLanguage(language);

    // Keep OpenMW's Morrowind Content Language in sync with the primary
    // preferred locale used by Runtime Localization and OpenMW l10n.
    // The secondary preferred locale is intentionally preserved and remains
    // configurable only from the in-game language settings.
    std::string primaryLocale = "en";
    if (language == QLatin1String("French"))
        primaryLocale = "fr";
    else if (language == QLatin1String("German"))
        primaryLocale = "de";
    else if (language == QLatin1String("Italian"))
        primaryLocale = "it";
    else if (language == QLatin1String("Polish"))
        primaryLocale = "pl";
    else if (language == QLatin1String("Russian"))
        primaryLocale = "ru";
    else if (language == QLatin1String("Spanish"))
        primaryLocale = "es";

    std::vector<std::string> preferredLocales = Settings::general().mPreferredLocales;
    if (preferredLocales.empty())
        preferredLocales.push_back(primaryLocale);
    else
        preferredLocales[0] = primaryLocale;
    Settings::general().mPreferredLocales.set(preferredLocales);

    if (language == QLatin1String("Polish"))
    {
        mGameSettings.setValue(QLatin1String("encoding"), { "win1250" });
    }
    else if (language == QLatin1String("Russian"))
    {
        mGameSettings.setValue(QLatin1String("encoding"), { "win1251" });
    }
    else
    {
        mGameSettings.setValue(QLatin1String("encoding"), { "win1252" });
    }
}

QList<Config::SettingValue> Launcher::DataFilesPage::selectedDirectoriesPaths() const
{
    QList<Config::SettingValue> dirList;
    for (int i = 0; i < ui.directoryListWidget->count(); ++i)
    {
        const QListWidgetItem* item = ui.directoryListWidget->item(i);
        if (item->flags() & Qt::ItemIsEnabled)
            dirList.append(qvariant_cast<Config::SettingValue>(item->data(Qt::UserRole)));
    }
    return dirList;
}

QList<Config::SettingValue> Launcher::DataFilesPage::selectedArchivePaths() const
{
    QList<Config::SettingValue> archiveList;
    for (int i = 0; i < ui.archiveListWidget->count(); ++i)
    {
        const QListWidgetItem* item = ui.archiveListWidget->item(i);
        if (item->checkState() == Qt::Checked)
            archiveList.append(qvariant_cast<Config::SettingValue>(item->data(Qt::UserRole)));
    }
    return archiveList;
}

QStringList Launcher::DataFilesPage::selectedFilePaths() const
{
    // retrieve the files selected for the profile
    ContentSelectorModel::ContentFileList items = mSelector->selectedFiles();
    QStringList filePaths;
    for (const ContentSelectorModel::EsmFile* item : items)
        if (QFile::exists(item->filePath()))
            filePaths.append(item->filePath());
    return filePaths;
}

void Launcher::DataFilesPage::removeProfile(const QString& profile)
{
    mLauncherSettings.removeContentList(profile);
}

QAbstractItemModel* Launcher::DataFilesPage::profilesModel() const
{
    return ui.profilesComboBox->model();
}

int Launcher::DataFilesPage::profilesIndex() const
{
    return ui.profilesComboBox->currentIndex();
}

void Launcher::DataFilesPage::setProfile(int index, bool savePrevious)
{
    if (index >= -1 && index < ui.profilesComboBox->count())
    {
        QString previous = mPreviousProfile;
        QString current = ui.profilesComboBox->itemText(index);

        mPreviousProfile = current;

        setProfile(previous, current, savePrevious);
    }
}

void Launcher::DataFilesPage::setProfile(const QString& previous, const QString& current, bool savePrevious)
{
    // abort if no change (poss. duplicate signal)
    if (previous == current)
        return;

    if (!previous.isEmpty() && savePrevious)
        saveSettings(previous);

    ui.profilesComboBox->setCurrentProfile(ui.profilesComboBox->findText(current));

    mNewDataDirs.clear();
    mKnownArchives.clear();
    populateFileViews(current);

    // save list of "old" bsa to be able to display "new" bsa in a different colour
    for (int i = 0; i < ui.archiveListWidget->count(); ++i)
    {
        auto* item = ui.archiveListWidget->item(i);
        mKnownArchives.push_back(item->text());
    }

    checkForDefaultProfile();
}

void Launcher::DataFilesPage::slotProfileDeleted(const QString& item)
{
    removeProfile(item);
}

void Launcher::DataFilesPage::refreshDataFilesView()
{
    QString currentProfile = ui.profilesComboBox->currentText();
    saveSettings(currentProfile);
    populateFileViews(currentProfile);
}

void Launcher::DataFilesPage::slotRefreshButtonClicked()
{
    refreshDataFilesView();
}

void Launcher::DataFilesPage::slotProfileChangedByUser(const QString& previous, const QString& current)
{
    setProfile(previous, current, true);
    emit signalProfileChanged(ui.profilesComboBox->findText(current));
}

void Launcher::DataFilesPage::slotProfileRenamed(const QString& previous, const QString& current)
{
    if (previous.isEmpty())
        return;

    // Save the new profile name
    saveSettings();

    // Remove the old one
    removeProfile(previous);

    loadSettings();
}

void Launcher::DataFilesPage::slotProfileChanged(int index)
{
    // in case the event was triggered externally
    if (ui.profilesComboBox->currentIndex() != index)
        ui.profilesComboBox->setCurrentIndex(index);

    setProfile(index, true);
}

void Launcher::DataFilesPage::on_newProfileAction_triggered()
{
    if (mNewProfileDialog->exec() != QDialog::Accepted)
        return;

    QString profile = mNewProfileDialog->lineEdit()->text();

    if (profile.isEmpty())
        return;

    saveSettings();

    mLauncherSettings.setCurrentContentListName(profile);

    addProfile(profile, true);
}

void Launcher::DataFilesPage::addProfile(const QString& profile, bool setAsCurrent)
{
    if (profile.isEmpty())
        return;

    if (ui.profilesComboBox->findText(profile) == -1)
        ui.profilesComboBox->addItem(profile);

    if (setAsCurrent)
        setProfile(ui.profilesComboBox->findText(profile), false);
}

void Launcher::DataFilesPage::on_cloneProfileAction_triggered()
{
    if (mCloneProfileDialog->exec() != QDialog::Accepted)
        return;

    QString profile = mCloneProfileDialog->lineEdit()->text();

    if (profile.isEmpty())
        return;

    const auto& dirList = selectedDirectoriesPaths();
    QStringList dirNames;
    for (const auto& dir : dirList)
    {
        if (mGameSettings.isUserSetting(dir))
            dirNames.push_back(dir.originalRepresentation);
    }
    QStringList archiveNames;
    for (const auto& archive : selectedArchivePaths())
    {
        if (mGameSettings.isUserSetting(archive))
            archiveNames.push_back(archive.originalRepresentation);
    }
    mLauncherSettings.setContentList(profile, dirNames, archiveNames, selectedFilePaths());
    addProfile(profile, true);
}

void Launcher::DataFilesPage::on_deleteProfileAction_triggered()
{
    QString profile = ui.profilesComboBox->currentText();

    if (profile.isEmpty())
        return;

    if (!showDeleteMessageBox(profile))
        return;

    // this should work since the Default profile can't be deleted and is always index 0
    int next = ui.profilesComboBox->currentIndex() - 1;

    // changing the profile forces a reload of plugin file views.
    ui.profilesComboBox->setCurrentIndex(next);

    removeProfile(profile);
    ui.profilesComboBox->removeItem(ui.profilesComboBox->findText(profile));

    checkForDefaultProfile();
}

void Launcher::DataFilesPage::updateNewProfileOkButton(const QString& text)
{
    // We do this here because we need the profiles combobox text
    mNewProfileDialog->setOkButtonEnabled(!text.isEmpty() && ui.profilesComboBox->findText(text) == -1);
}

void Launcher::DataFilesPage::updateCloneProfileOkButton(const QString& text)
{
    // We do this here because we need the profiles combobox text
    mCloneProfileDialog->setOkButtonEnabled(!text.isEmpty() && ui.profilesComboBox->findText(text) == -1);
}

void Launcher::DataFilesPage::addSubdirectories(bool append)
{
    int selectedRow = -1;
    if (append)
    {
        selectedRow = ui.directoryListWidget->count();
    }
    else
    {
        const QList<QPair<int, QListWidgetItem*>> sortedItems = sortedSelectedItems(ui.directoryListWidget);
        if (!sortedItems.isEmpty())
            selectedRow = sortedItems.first().first;
    }

    if (selectedRow == -1)
        return;

    QString rootPath = QFileDialog::getExistingDirectory(
        this, tr("Select Directory"), {}, QFileDialog::ShowDirsOnly | QFileDialog::Option::ReadOnly);

    if (rootPath.isEmpty())
        return;

    const QDir rootDir(rootPath);
    rootPath = rootDir.canonicalPath();

    QStringList subdirs;
    contentSubdirs(rootPath, subdirs);

    // Always offer to append the root directory just in case
    if (subdirs.isEmpty() || subdirs[0] != rootPath)
        subdirs.prepend(rootPath);
    else if (subdirs.size() == 1)
    {
        // We didn't find anything else that looks like a content directory
        // Automatically add the directory selected by user
        if (!ui.directoryListWidget->findItems(rootPath, Qt::MatchFixedString).isEmpty())
            return;
        ui.directoryListWidget->insertItem(selectedRow, rootPath);
        auto* item = ui.directoryListWidget->item(selectedRow);
        item->setData(Qt::UserRole, QVariant::fromValue(Config::SettingValue{ rootPath }));
        mNewDataDirs.push_back(rootPath);
        refreshDataFilesView();
        return;
    }

    mDirectoryPicker.dirListWidget->clear();

    for (const auto& dir : subdirs)
    {
        if (!ui.directoryListWidget->findItems(dir, Qt::MatchFixedString).isEmpty())
            continue;
        QListWidgetItem* newDir = new QListWidgetItem(dir, mDirectoryPicker.dirListWidget);
        newDir->setCheckState(Qt::Unchecked);
    }

    if (mDirectoryPickerDialog->exec() == QDialog::Rejected)
        return;

    for (int i = 0; i < mDirectoryPicker.dirListWidget->count(); ++i)
    {
        const auto* dir = mDirectoryPicker.dirListWidget->item(i);
        if (dir->checkState() == Qt::Checked)
        {
            ui.directoryListWidget->insertItem(selectedRow, dir->text());
            auto* item = ui.directoryListWidget->item(selectedRow);
            item->setData(Qt::UserRole, QVariant::fromValue(Config::SettingValue{ dir->text() }));
            mNewDataDirs.push_back(dir->text());
            ++selectedRow;
        }
    }

    refreshDataFilesView();
}

void Launcher::DataFilesPage::sortDirectories()
{
    // Ensure disabled entries (aka default directories) are always at the top.
    for (auto i = 1; i < ui.directoryListWidget->count(); ++i)
    {
        if (!(ui.directoryListWidget->item(i)->flags() & Qt::ItemIsEnabled)
            && (ui.directoryListWidget->item(i - 1)->flags() & Qt::ItemIsEnabled))
        {
            const auto item = ui.directoryListWidget->takeItem(i);
            ui.directoryListWidget->insertItem(i - 1, item);
            ui.directoryListWidget->setCurrentRow(i);
        }
    }

    updateAssetConflictStats();
}

void Launcher::DataFilesPage::sortArchives()
{
    // Ensure disabled entries (aka ones from non-user config files) are always at the top.
    for (auto i = 1; i < ui.archiveListWidget->count(); ++i)
    {
        if (!(ui.archiveListWidget->item(i)->flags() & Qt::ItemIsEnabled)
            && (ui.archiveListWidget->item(i - 1)->flags() & Qt::ItemIsEnabled))
        {
            const auto item = ui.archiveListWidget->takeItem(i);
            ui.archiveListWidget->insertItem(i - 1, item);
            ui.archiveListWidget->setCurrentRow(i);
        }
    }
}

void Launcher::DataFilesPage::removeDirectory()
{
    for (const auto& path : ui.directoryListWidget->selectedItems())
        ui.directoryListWidget->takeItem(ui.directoryListWidget->row(path));
    refreshDataFilesView();
}

void Launcher::DataFilesPage::showContextMenu(QMenu* menu, QListWidget* list, const QPoint& pos)
{
    QPoint globalPos = list->viewport()->mapToGlobal(pos);
    menu->exec(globalPos);
}

void Launcher::DataFilesPage::slotShowArchiveContextMenu(const QPoint& pos)
{
    showContextMenu(mArchiveContextMenu, ui.archiveListWidget, pos);
}

void Launcher::DataFilesPage::slotShowDataFilesContextMenu(const QPoint& pos)
{
    showContextMenu(mDataFilesContextMenu, ui.directoryListWidget, pos);
}

void Launcher::DataFilesPage::slotShowDirectoryPickerContextMenu(const QPoint& pos)
{
    showContextMenu(mDirectoryPickerMenu, mDirectoryPicker.dirListWidget, pos);
}

void Launcher::DataFilesPage::setCheckStateForMultiSelectedItems(QListWidget* list, Qt::CheckState checkState)
{
    for (QListWidgetItem* selectedItem : list->selectedItems())
    {
        selectedItem->setCheckState(checkState);
    }
}

void Launcher::DataFilesPage::moveSources(QListWidget* sourceList, int step)
{
    const QList<QPair<int, QListWidgetItem*>> sortedItems = sortedSelectedItems(sourceList, step > 0);
    for (const auto& i : sortedItems)
    {
        int selectedRow = sourceList->row(i.second);
        int newRow = selectedRow + step;
        if (selectedRow == -1 || newRow < 0 || newRow > sourceList->count() - 1)
            break;

        if (!(sourceList->item(newRow)->flags() & Qt::ItemIsEnabled))
            break;

        const auto item = sourceList->takeItem(selectedRow);
        sourceList->insertItem(newRow, item);
        sourceList->setCurrentRow(newRow);
    }

    if (sourceList == ui.directoryListWidget)
        updateAssetConflictStats();
}

void Launcher::DataFilesPage::addArchive(const QString& name, Qt::CheckState selected, int row)
{
    if (row == -1)
        row = ui.archiveListWidget->count();
    ui.archiveListWidget->insertItem(row, name);
    ui.archiveListWidget->item(row)->setCheckState(selected);
    ui.archiveListWidget->item(row)->setData(Qt::UserRole, QVariant::fromValue(Config::SettingValue{ name }));
    if (mKnownArchives.filter(name).isEmpty()) // XXX why contains doesn't work here ???
    {
        auto item = ui.archiveListWidget->item(row);
        QFont font = item->font();
        font.setBold(true);
        font.setItalic(true);
        item->setFont(font);
    }
}

void Launcher::DataFilesPage::addArchivesFromDir(const QString& path)
{
    QStringList archiveFilter{ "*.bsa", "*.ba2" };
    QDir dir(path);

    std::unordered_set<VFS::Path::Normalized, VFS::Path::Hash> archives;
    for (int i = 0; i < ui.archiveListWidget->count(); ++i)
        archives.insert(VFS::Path::normalizedFromQString(ui.archiveListWidget->item(i)->text()));

    for (const auto& fileinfo : dir.entryInfoList(archiveFilter))
    {
        const auto absPath = fileinfo.absoluteFilePath();
        if (Bsa::BSAFile::detectVersion(Files::pathFromQString(absPath)) == Bsa::BsaVersion::Unknown)
            continue;

        const auto fileName = fileinfo.fileName();

        if (archives.insert(VFS::Path::normalizedFromQString(fileName)).second)
            addArchive(fileName, Qt::Unchecked);
    }
}

void Launcher::DataFilesPage::checkForDefaultProfile()
{
    // don't allow deleting "Default" profile
    bool success = (ui.profilesComboBox->currentText() != mDefaultContentListName);

    ui.deleteProfileAction->setEnabled(success);
    ui.profilesComboBox->setEditEnabled(success);
}

bool Launcher::DataFilesPage::showDeleteMessageBox(const QString& text)
{
    QMessageBox msgBox(this);
    msgBox.setWindowTitle(tr("Delete Content List"));
    msgBox.setIcon(QMessageBox::Warning);
    msgBox.setStandardButtons(QMessageBox::Cancel);
    msgBox.setText(tr("Are you sure you want to delete <b>%1</b>?").arg(text));

    QAbstractButton* deleteButton = msgBox.addButton(tr("Delete"), QMessageBox::ActionRole);

    msgBox.exec();

    return (msgBox.clickedButton() == deleteButton);
}

void Launcher::DataFilesPage::slotAddonDataChanged()
{
    mReloadCellsTimer->start();
}

void Launcher::DataFilesPage::onReloadCellsTimerTimeout()
{
    const ContentSelectorModel::ContentFileList items = mSelector->selectedFiles();
    QStringList selectedFiles;
    for (const ContentSelectorModel::EsmFile* item : items)
        selectedFiles.append(item->filePath());

    if (mSelectedFiles != selectedFiles)
    {
        const std::lock_guard lock(mReloadCellsMutex);
        mSelectedFiles = std::move(selectedFiles);
        mReloadCells = true;
        mStartReloadCells.notify_one();
    }
}

void Launcher::DataFilesPage::reloadCells()
{
    QStringList selectedFiles;
    std::unique_lock lock(mReloadCellsMutex);

    while (true)
    {
        if (mAbortReloadCells)
            return;

        mStartReloadCells.wait(lock);

        if (mAbortReloadCells)
            return;

        if (!std::exchange(mReloadCells, false))
            continue;

        const QStringList newSelectedFiles = mSelectedFiles;

        lock.unlock();

        QStringList filteredFiles;
        for (const QString& v : newSelectedFiles)
            if (QFile::exists(v))
                filteredFiles.append(v);

        if (selectedFiles != filteredFiles)
        {
            selectedFiles = std::move(filteredFiles);

            CellNameLoader cellNameLoader;
            QSet<QString> set = cellNameLoader.getCellNames(selectedFiles);
            QStringList cellNamesList(set.begin(), set.end());
            std::sort(cellNamesList.begin(), cellNamesList.end());

            emit signalLoadedCellsChanged(std::move(cellNamesList));
        }

        lock.lock();
    }
}

void Launcher::DataFilesPage::startNavMeshTool()
{
    mMainDialog->writeSettings();

    ui.navMeshLogPlainTextEdit->clear();
    ui.navMeshProgressBar->setValue(0);
    ui.navMeshProgressBar->setMaximum(1);
    ui.navMeshProgressBar->resetFormat();

    mNavMeshToolProgress = NavMeshToolProgress{};

    QStringList arguments({ "--write-binary-log" });
    if (ui.navMeshRemoveUnusedTilesCheckBox->checkState() == Qt::Checked)
        arguments.append("--remove-unused-tiles");

    if (!mNavMeshToolInvoker->startProcess(QLatin1String("openmw-navmeshtool"), arguments))
        return;

    ui.cancelNavMeshButton->setEnabled(true);
    ui.navMeshProgressBar->setEnabled(true);
}

void Launcher::DataFilesPage::killNavMeshTool()
{
    mNavMeshToolInvoker->killProcess();
}

void Launcher::DataFilesPage::readNavMeshToolStderr()
{
    updateNavMeshProgress(4096);
}

void Launcher::DataFilesPage::updateNavMeshProgress(int minDataSize)
{
    if (!mNavMeshToolProgress.mEnabled)
        return;
    QProcess& process = *mNavMeshToolInvoker->getProcess();
    mNavMeshToolProgress.mMessagesData.append(process.readAllStandardError());
    if (mNavMeshToolProgress.mMessagesData.size() < minDataSize)
        return;
    const std::byte* const begin = reinterpret_cast<const std::byte*>(mNavMeshToolProgress.mMessagesData.constData());
    const std::byte* const end = begin + mNavMeshToolProgress.mMessagesData.size();
    const std::byte* position = begin;
    HandleNavMeshToolMessage handle{
        mNavMeshToolProgress.mCellsCount,
        mNavMeshToolProgress.mExpectedMaxProgress,
        ui.navMeshProgressBar->maximum(),
        ui.navMeshProgressBar->value(),
    };
    try
    {
        while (true)
        {
            NavMeshTool::Message message;
            const std::byte* const nextPosition = NavMeshTool::deserialize(position, end, message);
            if (nextPosition == position)
                break;
            position = nextPosition;
            handle = std::visit(handle, NavMeshTool::decode(message));
        }
    }
    catch (const std::exception& e)
    {
        Log(Debug::Error) << "Failed to deserialize navmeshtool message: " << e.what();
        mNavMeshToolProgress.mEnabled = false;
        ui.navMeshProgressBar->setFormat("Failed to update progress: " + QString(e.what()));
    }
    if (position != begin)
        mNavMeshToolProgress.mMessagesData = mNavMeshToolProgress.mMessagesData.mid(position - begin);
    mNavMeshToolProgress.mCellsCount = handle.mCellsCount;
    mNavMeshToolProgress.mExpectedMaxProgress = handle.mExpectedMaxProgress;
    ui.navMeshProgressBar->setMaximum(handle.mMaxProgress);
    ui.navMeshProgressBar->setValue(handle.mProgress);
}

void Launcher::DataFilesPage::readNavMeshToolStdout()
{
    QProcess& process = *mNavMeshToolInvoker->getProcess();
    QByteArray& logData = mNavMeshToolProgress.mLogData;
    logData.append(process.readAllStandardOutput());
    const int lineEnd = logData.lastIndexOf('\n');
    if (lineEnd == -1)
        return;
    const int size = logData.size() >= lineEnd && logData[lineEnd - 1] == '\r' ? lineEnd - 1 : lineEnd;
    ui.navMeshLogPlainTextEdit->appendPlainText(QString::fromUtf8(logData.data(), size));
    logData = logData.mid(lineEnd + 1);
}

void Launcher::DataFilesPage::navMeshToolFinished(int exitCode, QProcess::ExitStatus exitStatus)
{
    updateNavMeshProgress(0);
    ui.navMeshLogPlainTextEdit->appendPlainText(
        QString::fromUtf8(mNavMeshToolInvoker->getProcess()->readAllStandardOutput()));
    if (exitCode == 0 && exitStatus == QProcess::ExitStatus::NormalExit)
    {
        ui.navMeshProgressBar->setValue(ui.navMeshProgressBar->maximum());
        ui.navMeshProgressBar->resetFormat();
    }
    ui.cancelNavMeshButton->setEnabled(false);
    ui.navMeshProgressBar->setEnabled(false);
}
