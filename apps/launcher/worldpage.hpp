#ifndef OPENMW_LAUNCHER_WORLDPAGE_H
#define OPENMW_LAUNCHER_WORLDPAGE_H

#include <QString>
#include <QWidget>

namespace Files
{
    struct ConfigurationManager;
}

namespace Ui
{
    class WorldPage;
}

namespace Launcher
{
    class WorldPage : public QWidget
    {
        Q_OBJECT

    public:
        explicit WorldPage(const Files::ConfigurationManager& configurationManager, QWidget* parent = nullptr);
        ~WorldPage() override;

        bool loadSettings();
        void saveSettings();

    signals:
        void signalProceduralFloraSettingsChanged();

    private slots:
        void slotProceduralFloraToggled(bool checked);

    private:
        static constexpr int sWorldConfigVersion = 1;

        Ui::WorldPage* ui;
        QString mWorldSettingsPath;
    };
}

#endif
