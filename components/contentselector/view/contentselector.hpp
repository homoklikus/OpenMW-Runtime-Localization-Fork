#ifndef CONTENTSELECTOR_HPP
#define CONTENTSELECTOR_HPP

#include <memory>

#include <QComboBox>
#include <QDialog>
#include <QMenu>
#include <QToolButton>

#include <components/contentselector/model/contentmodel.hpp>

class QAction;
class QSortFilterProxyModel;

namespace Ui
{
    class ContentSelector;
}

namespace ContentSelectorView
{
    class ContentSelector : public QObject
    {
        Q_OBJECT

        QMenu* mContextMenu;
        QAction* mShowAssetConflictsAction = nullptr;
        QAction* mBrowseModFilesAction = nullptr;
        QAction* mShowNexusModAction = nullptr;
        QAction* mDeleteModAction = nullptr;

    protected:
        ContentSelectorModel::ContentModel* mContentModel;
        QSortFilterProxyModel* mAddonProxyModel;
        QString mManagedModsDirectory;

    public:
        explicit ContentSelector(QWidget* parent = nullptr, bool showOMWScripts = false);

        ~ContentSelector() override;

        QString currentFile() const;

        void addFiles(const QString& path, bool newfiles = false);
        void addAssetDirectory(const QString& path, bool newfiles = false);
        void sortFiles();
        bool containsDataFiles(const QString& path);
        bool containsAssetFiles(const QString& path) const;
        void clearConflictStats();
        void setDirectoryConflictStats(const QString& path, int conflicts, int wins, int losses);
        void setManagedModsDirectory(const QString& path);
        void clearFiles();
        void setNonUserContent(const QStringList& fileList);
        void setProfileContent(const QStringList& fileList);
        void setGroundcoverFiles(const QStringList& fileList);

        void clearCheckStates();
        void setEncoding(const QString& encoding);
        void setContentList(const QStringList& list);

        ContentSelectorModel::ContentFileList selectedFiles() const;
        QStringList groundcoverFiles() const;
        QString gameFilePath(const QStringList& contentFiles) const;

        void setGameFile(const QString& filename = QString(""));

        bool isGamefileSelected() const;

        QWidget* uiWidget() const;

        QComboBox* languageBox() const;

        QToolButton* refreshButton() const;

        QLineEdit* searchFilter() const;

    private:
        std::unique_ptr<Ui::ContentSelector> ui;

        void buildContentModel(bool showOMWScripts);
        void buildGameFileView();
        void buildAddonView();
        void buildContextMenu();
        void setGameFileSelected(int index, bool selected);
        void setCheckStateForMultiSelectedItems(Qt::CheckState checkState);
        void setGroundcoverForSelectedItems(bool enabled);
        QString selectedConflictDirectoryPath() const;
        QString selectedManagedModDirectory() const;
        QString selectedNexusModDirectory() const;

    signals:
        void signalCurrentGamefileIndexChanged(int);

        void signalAddonDataChanged(const QModelIndex& topleft, const QModelIndex& bottomright);
        void signalSelectedFilesChanged(QStringList selectedFiles);
        void signalGroundcoverChanged(bool enabled);
        void signalLoadOrderChanged();
        void signalDataDirectoryOrderChanged(QStringList paths);
        void signalShowAssetConflicts(QString path);
        void signalShowNexusModRequested(QString path);
        void signalDeleteModRequested(QString path);

    private slots:

        void slotCurrentGameFileIndexChanged(int index);
        void slotAddonTableItemActivated(const QModelIndex& index);
        void slotShowContextMenu(const QPoint& pos);
        void slotCheckMultiSelectedItems();
        void slotUncheckMultiSelectedItems();
        void slotCopySelectedItemsPaths();
        void slotBrowseModFiles();
        void slotShowAssetConflicts();
        void slotShowNexusMod();
        void slotDeleteMod();
        void slotSearchFilterTextChanged(const QString& newText);
        void slotSortFiles();
        void slotRowsMoved();
    };
}

#endif // CONTENTSELECTOR_HPP
