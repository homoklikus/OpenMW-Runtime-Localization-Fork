#include "worldpage.hpp"

#include <algorithm>
#include <array>

#include <QSettings>
#include <QSignalBlocker>

#include <components/files/configurationmanager.hpp>
#include <components/files/qtconversion.hpp>

#include "ui_worldpage.h"

namespace
{
    constexpr std::array<const char*, 3> floraSourceNames = {
        "automatic",
        "groundcover",
        "hybrid",
    };

    int floraSourceToIndex(const QString& value)
    {
        const QString normalized = value.trimmed().toLower();

        for (int i = 0; i < static_cast<int>(floraSourceNames.size()); ++i)
        {
            if (normalized == QString::fromLatin1(floraSourceNames[i]))
                return i;
        }

        return 0;
    }
}

namespace Launcher
{
    WorldPage::WorldPage(
        const Files::ConfigurationManager& configurationManager, QWidget* parent)
        : QWidget(parent)
        , ui(new Ui::WorldPage)
        , mWorldSettingsPath(
              Files::pathToQString(configurationManager.getUserConfigPath() / "world.cfg"))
    {
        ui->setupUi(this);

        loadSettings();

        connect(ui->proceduralFloraEnabledCheckBox, &QCheckBox::toggled, this,
            [this](bool checked) {
                slotProceduralFloraToggled(checked);
                emit signalProceduralFloraSettingsChanged();
            });

        connect(ui->proceduralFloraSourceComboBox,
            qOverload<int>(&QComboBox::currentIndexChanged), this,
            [this](int) { emit signalProceduralFloraSettingsChanged(); });

        connect(ui->proceduralFloraDensitySpinBox,
            qOverload<int>(&QSpinBox::valueChanged), this,
            [this](int) { emit signalProceduralFloraSettingsChanged(); });
    }

    WorldPage::~WorldPage()
    {
        delete ui;
    }

    bool WorldPage::loadSettings()
    {
        QSettings settings(mWorldSettingsPath, QSettings::IniFormat);

        const QSignalBlocker enabledBlocker(ui->proceduralFloraEnabledCheckBox);
        const QSignalBlocker sourceBlocker(ui->proceduralFloraSourceComboBox);
        const QSignalBlocker densityBlocker(ui->proceduralFloraDensitySpinBox);

        ui->proceduralFloraEnabledCheckBox->setChecked(
            settings.value("Flora/enabled", false).toBool());

        ui->proceduralFloraSourceComboBox->setCurrentIndex(
            floraSourceToIndex(settings.value("Flora/source", "automatic").toString()));

        const double density = std::clamp(
            settings.value("Flora/density", 1.0).toDouble(), 0.0, 2.0);
        ui->proceduralFloraDensitySpinBox->setValue(
            static_cast<int>(density * 100.0 + 0.5));

        slotProceduralFloraToggled(ui->proceduralFloraEnabledCheckBox->isChecked());
        return settings.status() == QSettings::NoError;
    }

    void WorldPage::saveSettings()
    {
        QSettings settings(mWorldSettingsPath, QSettings::IniFormat);

        settings.setValue("World/version", sWorldConfigVersion);

        settings.setValue(
            "Flora/enabled", ui->proceduralFloraEnabledCheckBox->isChecked());

        const int sourceIndex = std::clamp(
            ui->proceduralFloraSourceComboBox->currentIndex(), 0,
            static_cast<int>(floraSourceNames.size()) - 1);
        settings.setValue(
            "Flora/source", QString::fromLatin1(floraSourceNames[sourceIndex]));

        settings.setValue(
            "Flora/density",
            static_cast<double>(ui->proceduralFloraDensitySpinBox->value()) / 100.0);

        // Create the fauna section once world.cfg is written, but do not
        // overwrite it after future fauna settings are implemented.
        if (!settings.contains("Fauna/enabled"))
            settings.setValue("Fauna/enabled", false);

        settings.sync();
    }

    void WorldPage::slotProceduralFloraToggled(bool checked)
    {
        ui->proceduralFloraOptionsWidget->setEnabled(checked);
    }
}
