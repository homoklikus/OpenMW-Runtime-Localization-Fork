#include "datafilespage.hpp"
#include "maindialog.hpp"

#include <archive.h>
#include <archive_entry.h>

#include <QBrush>
#include <QClipboard>
#include <QColor>
#include <QAbstractItemView>
#include <QDebug>
#include <QDesktopServices>
#include <QDialogButtonBox>
#include <QDirIterator>
#include <QFile>
#include <QFileDialog>
#include <QHash>
#include <QHBoxLayout>
#include <QImageReader>
#include <QInputDialog>
#include <QLabel>
#include <QHeaderView>
#include <QList>
#include <QLineEdit>
#include <QMessageBox>
#include <QPair>
#include <QProgressDialog>
#include <QRegularExpression>
#include <QPushButton>
#include <QSet>
#include <QSignalBlocker>
#include <QSize>
#include <QTableWidget>
#include <QTemporaryDir>
#include <QTimer>
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

    // Dragging an asset-only row changes the real data= priority, not the
    // plugin content= order. Mirror the order to Data Directories, recalculate
    // conflict winners/losers and persist immediately.
    connect(mSelector, &ContentSelectorView::ContentSelector::signalAssetDirectoryOrderChanged, this,
        [this](const QStringList& paths) {
            applyAssetDirectoryOrder(paths);
            updateAssetConflictStats();
            mMainDialog->writeSettings();
        });

    connect(mSelector, &ContentSelectorView::ContentSelector::signalShowAssetConflicts, this,
        [this](const QString& path) { showAssetConflictDetails(path); });

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

    struct archive* archiveHandle = archive_read_new();
    if (!archiveHandle)
    {
        QMessageBox::critical(this, tr("Archive Analysis"), tr("Could not initialize the archive reader."));
        return;
    }

    archive_read_support_filter_all(archiveHandle);
    archive_read_support_format_all(archiveHandle);

    const QByteArray encodedPath = QFile::encodeName(archivePath);
    if (archive_read_open_filename(archiveHandle, encodedPath.constData(), 10240) != ARCHIVE_OK)
    {
        const char* error = archive_error_string(archiveHandle);
        const QString errorText = error ? QString::fromUtf8(error) : tr("Unknown error");
        archive_read_free(archiveHandle);
        QMessageBox::critical(this, tr("Archive Analysis"),
            tr("Could not open the archive:\n%1").arg(errorText));
        return;
    }

    QStringList filePaths;
    QString archiveFormat;
    struct archive_entry* entry = nullptr;
    int readResult = ARCHIVE_OK;

    while ((readResult = archive_read_next_header(archiveHandle, &entry)) == ARCHIVE_OK)
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

    QString archiveError;
    if (readResult != ARCHIVE_EOF)
    {
        const char* error = archive_error_string(archiveHandle);
        if (error)
            archiveError = QString::fromUtf8(error);
    }

    archive_read_free(archiveHandle);

    if (!archiveError.isEmpty())
    {
        QMessageBox::warning(this, tr("Archive Analysis"),
            tr("The archive was only partially read:\n%1").arg(archiveError));
    }

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

    static const QStringList rootFileExtensions{
        QStringLiteral("esm"),
        QStringLiteral("esp"),
        QStringLiteral("bsa"),
        QStringLiteral("ba2"),
        QStringLiteral("omwgame"),
        QStringLiteral("omwaddon"),
        QStringLiteral("omwscripts"),
    };

    QSet<QString> candidateRoots;

    for (const QString& path : filePaths)
    {
        const QStringList parts = path.split('/', Qt::SkipEmptyParts);
        if (parts.isEmpty())
            continue;

        bool foundRoot = false;
        for (int i = 0; i < parts.size(); ++i)
        {
            if (assetDirectories.contains(parts.at(i), Qt::CaseInsensitive))
            {
                candidateRoots.insert(parts.mid(0, i).join('/'));
                foundRoot = true;
                break;
            }
        }

        if (foundRoot)
            continue;

        const QString extension = QFileInfo(parts.constLast()).suffix().toLower();
        if (rootFileExtensions.contains(extension))
            candidateRoots.insert(parts.mid(0, parts.size() - 1).join('/'));
    }

    QStringList roots = candidateRoots.values();
    std::sort(roots.begin(), roots.end(),
        [](const QString& lhs, const QString& rhs) {
            return lhs.compare(rhs, Qt::CaseInsensitive) < 0;
        });

    QHash<QString, int> filesPerRoot;
    for (const QString& root : roots)
    {
        int count = 0;
        const QString prefix = root.isEmpty() ? QString() : root + '/';

        for (const QString& path : filePaths)
        {
            if (root.isEmpty() || path.startsWith(prefix, Qt::CaseInsensitive))
                ++count;
        }

        filesPerRoot.insert(root, count);
    }

    int numberedRoots = 0;
    for (const QString& root : roots)
    {
        const QString firstSegment = root.section('/', 0, 0).trimmed();
        if (firstSegment.size() >= 2 && firstSegment.at(0).isDigit() && firstSegment.at(1).isDigit())
            ++numberedRoots;
    }

    QString layoutType;
    if (roots.isEmpty())
        layoutType = tr("No recognizable Morrowind data root");
    else if (roots.size() == 1)
    {
        if (roots.constFirst().isEmpty())
            layoutType = tr("Simple mod (data files at archive root)");
        else
            layoutType = tr("Single wrapped data root");
    }
    else if (numberedRoots >= 2)
        layoutType = tr("BAIN-like package with multiple subpackages");
    else
        layoutType = tr("Multiple possible data roots");

    QDialog dialog(this);
    dialog.setWindowTitle(tr("Archive Analysis — %1").arg(QFileInfo(archivePath).fileName()));
    dialog.resize(850, 520);

    auto* layout = new QVBoxLayout(&dialog);

    auto* summary = new QLabel(
        tr("Archive: %1\nFormat: %2\nFiles: %3\nDetected layout: %4")
            .arg(QFileInfo(archivePath).fileName())
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
    auto* modNameLabel = new QLabel(tr("Mod name:"), &dialog);
    auto* modNameEdit = new QLineEdit(QFileInfo(archivePath).completeBaseName(), &dialog);
    modNameEdit->setToolTip(tr("The mod will be installed as one subdirectory of the configured Mods Directory."));
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

    QString destinationPath = QDir(modsDirectory).filePath(modName);
    bool replaceExisting = false;

    if (QFileInfo::exists(destinationPath))
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

    struct archive* installArchive = archive_read_new();
    if (!installArchive)
    {
        QMessageBox::critical(this, tr("Install Mod"), tr("Could not initialize the archive reader."));
        return;
    }

    archive_read_support_filter_all(installArchive);
    archive_read_support_format_all(installArchive);

    if (archive_read_open_filename(installArchive, encodedPath.constData(), 10240) != ARCHIVE_OK)
    {
        const char* error = archive_error_string(installArchive);
        const QString errorText = error ? QString::fromUtf8(error) : tr("Unknown error");
        archive_read_free(installArchive);
        QMessageBox::critical(this, tr("Install Mod"),
            tr("Could not reopen the archive for installation:\n%1").arg(errorText));
        return;
    }

    bool installFailed = false;
    QString installError;
    int installedFiles = 0;

    struct archive_entry* installEntry = nullptr;
    int installReadResult = ARCHIVE_OK;

    while ((installReadResult = archive_read_next_header(installArchive, &installEntry)) == ARCHIVE_OK)
    {
        if (archive_entry_filetype(installEntry) != AE_IFREG
            || archive_entry_symlink(installEntry) != nullptr
            || archive_entry_hardlink(installEntry) != nullptr)
        {
            archive_read_data_skip(installArchive);
            continue;
        }

        const char* rawPath = archive_entry_pathname_utf8(installEntry);
        if (!rawPath)
            rawPath = archive_entry_pathname(installEntry);
        if (!rawPath)
        {
            archive_read_data_skip(installArchive);
            continue;
        }

        QString archiveEntryPath = QString::fromUtf8(rawPath).trimmed();
        archiveEntryPath.replace('\\', '/');
        while (archiveEntryPath.startsWith(QLatin1String("./")))
            archiveEntryPath.remove(0, 2);
        while (archiveEntryPath.startsWith('/'))
            archiveEntryPath.remove(0, 1);

        bool extractedThisEntry = false;

        for (const int row : selectedRows)
        {
            const QString& root = roots.at(row);
            const QString prefix = root.isEmpty() ? QString() : root + '/';

            QString relativePath;
            if (root.isEmpty())
                relativePath = archiveEntryPath;
            else if (archiveEntryPath.startsWith(prefix, Qt::CaseInsensitive))
                relativePath = archiveEntryPath.mid(prefix.size());
            else
                continue;

            relativePath.replace('\\', '/');
            while (relativePath.startsWith(QLatin1String("./")))
                relativePath.remove(0, 2);

            const QString normalizedRelativePath = relativePath.toLower();
            if (!filesByRoot.value(root).contains(normalizedRelativePath)
                || finalOwner.value(normalizedRelativePath, -1) != row)
                continue;

            const QStringList pathParts = relativePath.split('/', Qt::KeepEmptyParts);
            bool unsafePath = relativePath.isEmpty() || QDir::isAbsolutePath(relativePath);
            for (const QString& part : pathParts)
            {
                if (part.isEmpty() || part == QLatin1String(".") || part == QLatin1String("..")
                    || part.contains(':'))
                {
                    unsafePath = true;
                    break;
                }
            }

            if (unsafePath)
            {
                installFailed = true;
                installError = tr("The archive contains an unsafe path:\n%1").arg(relativePath);
                break;
            }

            const QString outputPath = QDir(stagingDir.path()).filePath(relativePath);
            const QString outputDirectory = QFileInfo(outputPath).absolutePath();

            if (!QDir().mkpath(outputDirectory))
            {
                installFailed = true;
                installError = tr("Could not create directory:\n%1").arg(outputDirectory);
                break;
            }

            QFile outputFile(outputPath);
            if (!outputFile.open(QIODevice::WriteOnly | QIODevice::Truncate))
            {
                installFailed = true;
                installError = tr("Could not write file:\n%1").arg(outputPath);
                break;
            }

            char buffer[64 * 1024];
            while (true)
            {
                const la_ssize_t bytesRead = archive_read_data(installArchive, buffer, sizeof(buffer));
                if (bytesRead == 0)
                    break;

                if (bytesRead < 0)
                {
                    const char* error = archive_error_string(installArchive);
                    installFailed = true;
                    installError = tr("Could not read archive data:\n%1")
                        .arg(error ? QString::fromUtf8(error) : tr("Unknown error"));
                    break;
                }

                if (outputFile.write(buffer, bytesRead) != bytesRead)
                {
                    installFailed = true;
                    installError = tr("Could not write file:\n%1").arg(outputPath);
                    break;
                }
            }

            outputFile.close();

            if (installFailed)
                break;

            ++installedFiles;
            extractedThisEntry = true;
            break;
        }

        if (installFailed)
            break;

        if (!extractedThisEntry)
            archive_read_data_skip(installArchive);
    }

    if (!installFailed && installReadResult != ARCHIVE_EOF)
    {
        const char* error = archive_error_string(installArchive);
        installFailed = true;
        installError = tr("Could not finish reading the archive:\n%1")
            .arg(error ? QString::fromUtf8(error) : tr("Unknown error"));
    }

    archive_read_free(installArchive);

    if (installFailed)
    {
        QMessageBox::critical(this, tr("Install Mod"), installError);
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

void Launcher::DataFilesPage::applyAssetDirectoryOrder(const QStringList& paths)
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

    QVector<int> assetSlots;
    QHash<QString, QListWidgetItem*> assetItems;

    for (int i = 0; i < allItems.size(); ++i)
    {
        QListWidgetItem* item = allItems.at(i);
        const Config::SettingValue setting = qvariant_cast<Config::SettingValue>(item->data(Qt::UserRole));
        const QString normalizedPath = QDir::cleanPath(QFileInfo(setting.value).absoluteFilePath());

        if (normalizedOrder.contains(normalizedPath, Qt::CaseInsensitive))
        {
            assetSlots.push_back(i);
            assetItems.insert(normalizedPath.toLower(), item);
        }
    }

    if (assetSlots.size() == normalizedOrder.size())
    {
        for (int i = 0; i < assetSlots.size(); ++i)
        {
            QListWidgetItem* item = assetItems.value(normalizedOrder.at(i).toLower(), nullptr);
            if (item)
                allItems[assetSlots.at(i)] = item;
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
