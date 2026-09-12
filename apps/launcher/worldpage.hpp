#ifndef OPENMW_LAUNCHER_WORLDPAGE_H
#define OPENMW_LAUNCHER_WORLDPAGE_H

#include <QWidget>

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
        explicit WorldPage(QWidget* parent = nullptr);
        ~WorldPage() override;

    private:
        Ui::WorldPage* ui;
    };
}

#endif
