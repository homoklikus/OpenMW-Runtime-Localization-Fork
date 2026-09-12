#include "worldpage.hpp"

#include "ui_worldpage.h"

namespace Launcher
{
    WorldPage::WorldPage(QWidget* parent)
        : QWidget(parent)
        , ui(new Ui::WorldPage)
    {
        ui->setupUi(this);
    }

    WorldPage::~WorldPage()
    {
        delete ui;
    }
}
