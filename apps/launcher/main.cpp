#include <iostream>

#include <QCryptographicHash>
#include <QDir>
#include <QLocalServer>
#include <QLocalSocket>
#include <QTimer>

#include <boost/program_options/options_description.hpp>
#include <boost/program_options/variables_map.hpp>

#include <components/debug/debugging.hpp>
#include <components/files/configurationmanager.hpp>
#include <components/files/qtconversion.hpp>
#include <components/l10n/qttranslations.hpp>
#include <components/platform/application.hpp>
#include <components/platform/platform.hpp>

#ifdef MAC_OS_X_VERSION_MIN_REQUIRED
#undef MAC_OS_X_VERSION_MIN_REQUIRED
// We need to do this because of Qt: https://bugreports.qt-project.org/browse/QTBUG-22154
#define MAC_OS_X_VERSION_MIN_REQUIRED __ENVIRONMENT_MAC_OS_X_VERSION_MIN_REQUIRED__
#endif // MAC_OS_X_VERSION_MIN_REQUIRED

#include "maindialog.hpp"

namespace
{
    QString nxmIpcServerName()
    {
        // Keep the rendezvous stable between separately launched processes,
        // but isolate users on a multi-user machine.
        const QByteArray userHash
            = QCryptographicHash::hash(QDir::homePath().toUtf8(), QCryptographicHash::Sha256)
                  .toHex()
                  .left(16);
        return QStringLiteral("openmw-runtime-localization-fork-nxm-%1").arg(QString::fromLatin1(userHash));
    }

    QString nxmArgument(int argc, char* argv[])
    {
        for (int i = 1; i < argc; ++i)
        {
            const QString argument = QString::fromLocal8Bit(argv[i]).trimmed();
            if (argument.startsWith(QStringLiteral("nxm://"), Qt::CaseInsensitive))
                return argument;
        }

        return {};
    }

    bool relayNxmUrl(const QString& serverName, const QString& nxmUrl)
    {
        if (nxmUrl.isEmpty())
            return false;

        QLocalSocket socket;
        socket.connectToServer(serverName, QIODevice::WriteOnly);
        if (!socket.waitForConnected(750))
            return false;

        const QByteArray payload = nxmUrl.toUtf8();
        if (socket.write(payload) != payload.size())
            return false;

        if (!socket.waitForBytesWritten(1000))
            return false;

        socket.disconnectFromServer();
        return true;
    }

    bool listenForNxmUrls(QLocalServer& server, const QString& serverName)
    {
        if (server.listen(serverName))
            return true;

        // A failed listen can mean either a live launcher or a stale Unix
        // socket left after an abnormal exit. Never remove a live endpoint.
        QLocalSocket probe;
        probe.connectToServer(serverName, QIODevice::WriteOnly);
        if (probe.waitForConnected(250))
        {
            probe.disconnectFromServer();
            return false;
        }

        QLocalServer::removeServer(serverName);
        return server.listen(serverName);
    }
}

int runLauncher(int argc, char* argv[])
{
    Platform::init();

    const QString startupNxmUrl = nxmArgument(argc, argv);

    boost::program_options::variables_map variables;
    boost::program_options::options_description description;
    Files::ConfigurationManager configurationManager;
    configurationManager.addCommonOptions(description);
    configurationManager.readConfiguration(variables, description, true);

    Debug::setupLogging(configurationManager.getLogPath(), "Launcher");

    try
    {
        Platform::Application app(argc, argv);

        const QString ipcServerName = nxmIpcServerName();

        // A browser invokes the registered nxm:// handler as a second launcher
        // process. If the real launcher is already running, this tiny relay
        // sends the URL to it and exits before creating another window.
        if (!startupNxmUrl.isEmpty() && relayNxmUrl(ipcServerName, startupNxmUrl))
            return 0;

        QLocalServer nxmServer;
        const bool ownsNxmServer = listenForNxmUrls(nxmServer, ipcServerName);

        // Cover the small race where another launcher started listening after
        // the first relay attempt.
        if (!startupNxmUrl.isEmpty() && !ownsNxmServer
            && relayNxmUrl(ipcServerName, startupNxmUrl))
            return 0;

        QString resourcesPath(".");
        if (!variables["resources"].empty())
        {
            resourcesPath = Files::pathToQString(variables["resources"].as<Files::MaybeQuotedPath>().u8string());
        }

        L10n::installQtTranslations(app, "launcher", resourcesPath);

        Launcher::MainDialog mainWin(configurationManager);

        Launcher::FirstRunDialogResult result = mainWin.showFirstRunDialog();
        if (result == Launcher::FirstRunDialogResultFailure)
            return 0;

        if (result == Launcher::FirstRunDialogResultContinue)
            mainWin.show();

        if (ownsNxmServer)
        {
            const auto receivePendingNxmUrls = [&nxmServer, &mainWin]() {
                while (nxmServer.hasPendingConnections())
                {
                    QLocalSocket* socket = nxmServer.nextPendingConnection();
                    if (!socket)
                        continue;

                    if (socket->bytesAvailable() == 0)
                        socket->waitForReadyRead(1000);

                    const QString nxmUrl = QString::fromUtf8(socket->readAll()).trimmed();
                    socket->disconnectFromServer();
                    socket->deleteLater();

                    if (!nxmUrl.isEmpty())
                        mainWin.handleNxmUrl(nxmUrl);
                }
            };

            QObject::connect(
                &nxmServer, &QLocalServer::newConnection, &app, receivePendingNxmUrls);

            // A browser may have connected while the launcher was still
            // finishing setup, before the newConnection signal was connected.
            receivePendingNxmUrls();
        }

        // If no launcher was running when an nxm:// URL started this process,
        // handle it after the window and Data Files page are fully initialized.
        if (!startupNxmUrl.isEmpty() && ownsNxmServer)
        {
            QTimer::singleShot(0, &mainWin,
                [&mainWin, startupNxmUrl]() { mainWin.handleNxmUrl(startupNxmUrl); });
        }

        int exitCode = app.exec();

        return exitCode;
    }
    catch (const std::exception& e)
    {
        Log(Debug::Error) << "Unexpected exception: " << e.what();
        return 0;
    }
}

int main(int argc, char* argv[])
{
    return Debug::wrapApplication(runLauncher, argc, argv, "Launcher");
}
