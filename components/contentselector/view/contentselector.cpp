#include "contentselector.hpp"

#include "ui_contentselector.h"

#include <components/contentselector/model/esmfile.hpp>

#include <algorithm>
#include <QApplication>
#include <QPainter>
#include <QStyle>
#include <QStyledItemDelegate>
#include <QStyleOptionViewItem>
#include <QClipboard>
#include <QDesktopServices>
#include <QDir>
#include <QFileInfo>
#include <QHeaderView>
#include <QMenu>
#include <QModelIndex>
#include <QProgressDialog>
#include <QSortFilterProxyModel>
#include <QUrl>
namespace
{
    class StatusItemDelegate final : public QStyledItemDelegate
    {
    public:
        using QStyledItemDelegate::QStyledItemDelegate;

        void paint(QPainter* painter, const QStyleOptionViewItem& option, const QModelIndex& index) const override
        {
            QStyleOptionViewItem opt(option);
            initStyleOption(&opt, index);

            // Groundcover: Status contains only an icon. QStyledItemDelegate
            // normally places DecorationRole on the left, so center it here.
            if (opt.text.isEmpty() && !opt.icon.isNull())
            {
                const QIcon icon = opt.icon;
                opt.icon = QIcon();

                QStyle* style = opt.widget ? opt.widget->style() : QApplication::style();
                style->drawControl(QStyle::CE_ItemViewItem, &opt, painter, opt.widget);

                const int side = std::min({ 16, option.rect.width(), option.rect.height() });
                const QRect iconRect(
                    option.rect.center().x() - side / 2,
                    option.rect.center().y() - side / 2,
                    side,
                    side);

                const QIcon::Mode mode
                    = (option.state & QStyle::State_Enabled) ? QIcon::Normal : QIcon::Disabled;
                const QIcon::State state
                    = (option.state & QStyle::State_Selected) ? QIcon::On : QIcon::Off;

                icon.paint(painter, iconRect, Qt::AlignCenter, mode, state);
                return;
            }

            QStyledItemDelegate::paint(painter, option, index);
        }
    };
}

ContentSelectorView::ContentSelector::ContentSelector(QWidget* parent, bool showOMWScripts)
    : QObject(parent)
    , ui(std::make_unique<Ui::ContentSelector>())
{
    ui->setupUi(parent);
    ui->addonView->setDragDropMode(QAbstractItemView::InternalMove);

    if (!showOMWScripts)
    {
        ui->languageComboBox->setHidden(true);
        ui->sortButton->setHidden(true);
        ui->refreshButton->setHidden(true);
    }

    buildContentModel(showOMWScripts);
    buildGameFileView();
    buildAddonView();
}

ContentSelectorView::ContentSelector::~ContentSelector() = default;

void ContentSelectorView::ContentSelector::buildContentModel(bool showOMWScripts)
{
    QIcon warningIcon(ui->addonView->style()->standardIcon(QStyle::SP_MessageBoxWarning));
    QIcon errorIcon(ui->addonView->style()->standardIcon(QStyle::SP_MessageBoxCritical));
    mContentModel = new ContentSelectorModel::ContentModel(this, warningIcon, errorIcon, showOMWScripts);
}

void ContentSelectorView::ContentSelector::buildGameFileView()
{
    ui->gameFileView->addItem(tr("<No game file>"));
    ui->gameFileView->setVisible(true);

    connect(ui->gameFileView, qOverload<int>(&ComboBox::currentIndexChanged), this,
        &ContentSelector::slotCurrentGameFileIndexChanged);

    ui->gameFileView->setCurrentIndex(0);
}

class AddOnProxyModel : public QSortFilterProxyModel
{
public:
    explicit AddOnProxyModel(QObject* parent = nullptr)
        : QSortFilterProxyModel(parent)
    {
    }

    bool filterAcceptsRow(int sourceRow, const QModelIndex& sourceParent) const override
    {
        static const QString contentTypeAddon
            = QString::number(static_cast<int>(ContentSelectorModel::ContentType_Addon));

        QModelIndex nameIndex = sourceModel()->index(
            sourceRow, ContentSelectorModel::ContentModel::Column_FileName, sourceParent);
        const QString userRole = sourceModel()->data(nameIndex, Qt::UserRole).toString();

        return QSortFilterProxyModel::filterAcceptsRow(sourceRow, sourceParent) && userRole == contentTypeAddon;
    }
};

bool ContentSelectorView::ContentSelector::isGamefileSelected() const
{
    return ui->gameFileView->currentIndex() > 0;
}

QWidget* ContentSelectorView::ContentSelector::uiWidget() const
{
    return ui->contentGroupBox;
}

QComboBox* ContentSelectorView::ContentSelector::languageBox() const
{
    return ui->languageComboBox;
}

QToolButton* ContentSelectorView::ContentSelector::refreshButton() const
{
    return ui->refreshButton;
}

QLineEdit* ContentSelectorView::ContentSelector::searchFilter() const
{
    return ui->searchFilter;
}

void ContentSelectorView::ContentSelector::buildAddonView()
{
    ui->addonView->setVisible(true);

    mAddonProxyModel = new AddOnProxyModel(this);
    mAddonProxyModel->setFilterRegularExpression(searchFilter()->text());
    mAddonProxyModel->setFilterCaseSensitivity(Qt::CaseInsensitive);
    mAddonProxyModel->setFilterKeyColumn(ContentSelectorModel::ContentModel::Column_FileName);
    mAddonProxyModel->setDynamicSortFilter(true);
    mAddonProxyModel->setSourceModel(mContentModel);

    connect(ui->searchFilter, &QLineEdit::textEdited, mAddonProxyModel, &QSortFilterProxyModel::setFilterWildcard);
    connect(ui->searchFilter, &QLineEdit::textEdited, this, &ContentSelector::slotSearchFilterTextChanged);
    connect(ui->sortButton, &QToolButton::clicked, this, &ContentSelector::slotSortFiles);

    ui->addonView->setModel(mAddonProxyModel);
    ui->addonView->setItemDelegateForColumn(
        ContentSelectorModel::ContentModel::Column_Status, new StatusItemDelegate(ui->addonView));

    QHeaderView* header = ui->addonView->horizontalHeader();
    header->moveSection(
        header->visualIndex(ContentSelectorModel::ContentModel::Column_Number), 0);
    header->setSectionResizeMode(
        ContentSelectorModel::ContentModel::Column_Number, QHeaderView::ResizeToContents);
    header->setSectionResizeMode(
        ContentSelectorModel::ContentModel::Column_FileName, QHeaderView::Stretch);
    header->setSectionResizeMode(
        ContentSelectorModel::ContentModel::Column_Status, QHeaderView::ResizeToContents);

    connect(ui->addonView, &QTableView::activated, this, &ContentSelector::slotAddonTableItemActivated);
    connect(mContentModel, &ContentSelectorModel::ContentModel::dataChanged, this,
        &ContentSelector::signalAddonDataChanged);
    connect(mContentModel, &ContentSelectorModel::ContentModel::signalDataDirectoryOrderChanged, this,
        &ContentSelector::signalDataDirectoryOrderChanged);
    connect(mContentModel, &ContentSelectorModel::ContentModel::dataChanged, this, &ContentSelector::slotRowsMoved);
    buildContextMenu();
}

void ContentSelectorView::ContentSelector::buildContextMenu()
{
    ui->addonView->setContextMenuPolicy(Qt::CustomContextMenu);
    connect(ui->addonView, &QTableView::customContextMenuRequested, this, &ContentSelector::slotShowContextMenu);

    mContextMenu = new QMenu(ui->addonView);
    mContextMenu->addAction(tr("&Check Selected"), this, SLOT(slotCheckMultiSelectedItems()));
    mContextMenu->addAction(tr("&Uncheck Selected"), this, SLOT(slotUncheckMultiSelectedItems()));
    mContextMenu->addAction(tr("&Copy Path(s) to Clipboard"), this, SLOT(slotCopySelectedItemsPaths()));
    mBrowseModFilesAction
        = mContextMenu->addAction(tr("Browse Mod Files"), this, SLOT(slotBrowseModFiles()));
    mShowAssetConflictsAction
        = mContextMenu->addAction(tr("Show Asset Conflicts..."), this, SLOT(slotShowAssetConflicts()));

    mContextMenu->addSeparator();
    mShowNexusModAction
        = mContextMenu->addAction(tr("Show on Nexus Mods"), this, SLOT(slotShowNexusMod()));
    mShowNexusModAction->setVisible(false);
    mDeleteModAction = mContextMenu->addAction(tr("Delete Mod..."), this, SLOT(slotDeleteMod()));

    mContextMenu->addSeparator();
    mContextMenu->addAction(tr("Mark Selected as Groundcover"), this,
        [this]() { setGroundcoverForSelectedItems(true); });
    mContextMenu->addAction(tr("Unmark Selected as Groundcover"), this,
        [this]() { setGroundcoverForSelectedItems(false); });
}

void ContentSelectorView::ContentSelector::setNonUserContent(const QStringList& fileList)
{
    mContentModel->setNonUserContent(fileList);
}

void ContentSelectorView::ContentSelector::setProfileContent(const QStringList& fileList)
{
    clearCheckStates();

    for (const QString& filepath : fileList)
    {
        const ContentSelectorModel::EsmFile* file = mContentModel->item(filepath);
        if (file && file->isGameFile())
        {
            setGameFile(filepath);
            break;
        }
    }

    setContentList(fileList);
}

void ContentSelectorView::ContentSelector::setGroundcoverFiles(const QStringList& fileList)
{
    mContentModel->setGroundcoverFiles(fileList);
}

void ContentSelectorView::ContentSelector::setGameFile(const QString& filename)
{
    int index = 0;

    if (!filename.isEmpty())
    {
        const ContentSelectorModel::EsmFile* file = mContentModel->item(filename);
        index = ui->gameFileView->findText(file->fileName());

        // verify that the current index is also checked in the model
        if (!mContentModel->isChecked(file) && !mContentModel->setCheckState(file, true))
        {
            // throw error in case file not found?
            return;
        }
    }

    ui->gameFileView->setCurrentIndex(index);
}

void ContentSelectorView::ContentSelector::clearCheckStates()
{
    mContentModel->uncheckAll();
}

void ContentSelectorView::ContentSelector::setEncoding(const QString& encoding)
{
    mContentModel->setEncoding(encoding);
}

void ContentSelectorView::ContentSelector::setContentList(const QStringList& list)
{
    if (list.isEmpty())
    {
        slotCurrentGameFileIndexChanged(ui->gameFileView->currentIndex());
    }
    else
        mContentModel->setContentList(list);
}

ContentSelectorModel::ContentFileList ContentSelectorView::ContentSelector::selectedFiles() const
{
    if (!mContentModel)
        return ContentSelectorModel::ContentFileList();

    return mContentModel->checkedItems();
}

QStringList ContentSelectorView::ContentSelector::groundcoverFiles() const
{
    if (!mContentModel)
        return {};

    return mContentModel->groundcoverFiles();
}

QString ContentSelectorView::ContentSelector::gameFilePath(const QStringList& contentFiles) const
{
    if (!mContentModel)
        return {};

    for (const QString& fileName : contentFiles)
    {
        const ContentSelectorModel::EsmFile* file = mContentModel->item(fileName);
        if (file && file->isGameFile() && !file->filePath().isEmpty())
            return file->filePath();
    }

    return {};
}

void ContentSelectorView::ContentSelector::addFiles(const QString& path, bool newfiles)
{
    mContentModel->addFiles(path, newfiles);

    // add any game files to the combo box
    for (const QString& gameFileName : mContentModel->gameFiles())
    {
        if (ui->gameFileView->findText(gameFileName) == -1)
        {
            ui->gameFileView->addItem(gameFileName);
        }
    }

    if (ui->gameFileView->currentIndex() != 0)
        ui->gameFileView->setCurrentIndex(0);

    mContentModel->uncheckAll();
}

void ContentSelectorView::ContentSelector::addAssetDirectory(const QString& path, bool newfiles)
{
    mContentModel->addAssetDirectory(path, newfiles);
}

void ContentSelectorView::ContentSelector::sortFiles()
{
    mContentModel->sortFiles();
}

bool ContentSelectorView::ContentSelector::containsDataFiles(const QString& path)
{
    return mContentModel->containsDataFiles(path);
}

bool ContentSelectorView::ContentSelector::containsAssetFiles(const QString& path) const
{
    return mContentModel->containsAssetFiles(path);
}

void ContentSelectorView::ContentSelector::setManagedModsDirectory(const QString& path)
{
    if (path.isEmpty())
    {
        mManagedModsDirectory.clear();
        return;
    }

    mManagedModsDirectory = QDir::cleanPath(QFileInfo(path).absoluteFilePath());
}

void ContentSelectorView::ContentSelector::clearConflictStats()
{
    mContentModel->clearConflictStats();
}

void ContentSelectorView::ContentSelector::setDirectoryConflictStats(
    const QString& path, int conflicts, int wins, int losses)
{
    mContentModel->setDirectoryConflictStats(path, conflicts, wins, losses);
}

void ContentSelectorView::ContentSelector::clearFiles()
{
    mContentModel->clearFiles();
}

QString ContentSelectorView::ContentSelector::currentFile() const
{
    QModelIndex currentIdx = ui->addonView->currentIndex();

    if (!currentIdx.isValid() && ui->gameFileView->currentIndex() > 0)
        return ui->gameFileView->currentText();

    QModelIndex idx = mContentModel->index(mAddonProxyModel->mapToSource(currentIdx).row(),
        ContentSelectorModel::ContentModel::Column_FileName, QModelIndex());

    // DisplayRole may include launcher-only package metadata such as the
    // managed mod version. Keep currentFile() as the real plugin identifier.
    return mContentModel->data(idx, Qt::EditRole).toString();
}

void ContentSelectorView::ContentSelector::slotCurrentGameFileIndexChanged(int index)
{
    static int oldIndex = -1;

    if (index != oldIndex)
    {
        if (oldIndex > -1)
        {
            setGameFileSelected(oldIndex, false);
        }

        oldIndex = index;

        setGameFileSelected(index, true);
    }

    emit signalCurrentGamefileIndexChanged(index);
}

void ContentSelectorView::ContentSelector::setGameFileSelected(int index, bool selected)
{
    QString fileName = ui->gameFileView->itemText(index);
    const ContentSelectorModel::EsmFile* file = mContentModel->item(fileName);
    if (file != nullptr)
    {
        QModelIndex index2(mContentModel->indexFromItem(file));
        mContentModel->setData(index2, selected, Qt::UserRole + 1);
    }
    mContentModel->setCurrentGameFile(selected ? file : nullptr);
}

void ContentSelectorView::ContentSelector::slotAddonTableItemActivated(const QModelIndex& index)
{
    // toggles check state when an AddOn file is double clicked or activated by keyboard
    QModelIndex sourceIndex = mAddonProxyModel->mapToSource(index).siblingAtColumn(
        ContentSelectorModel::ContentModel::Column_FileName);

    if (!mContentModel->isEnabled(sourceIndex))
        return;

    Qt::CheckState checkState = Qt::Unchecked;

    if (mContentModel->data(sourceIndex, Qt::CheckStateRole).toInt() == Qt::Unchecked)
        checkState = Qt::Checked;

    mContentModel->setData(sourceIndex, checkState, Qt::CheckStateRole);
}

QString ContentSelectorView::ContentSelector::selectedManagedModDirectory() const
{
    if (mManagedModsDirectory.isEmpty())
        return {};

    const QModelIndexList selectedIndexes
        = ui->addonView->selectionModel()->selectedRows(ContentSelectorModel::ContentModel::Column_FileName);

    if (selectedIndexes.size() != 1)
        return {};

    const QModelIndex sourceIndex = mAddonProxyModel->mapToSource(selectedIndexes.constFirst());
    const ContentSelectorModel::EsmFile* file = mContentModel->item(sourceIndex.row());

    if (!file || file->filePath().isEmpty() || file->builtIn() || file->fromAnotherConfigFile())
        return {};

    QString currentPath = file->isAssetDirectory()
        ? QFileInfo(file->filePath()).absoluteFilePath()
        : QFileInfo(file->filePath()).absolutePath();

    currentPath = QDir::cleanPath(currentPath);
    const QString rootPath = QDir::cleanPath(QFileInfo(mManagedModsDirectory).absoluteFilePath());

#ifdef Q_OS_WINDOWS
    constexpr Qt::CaseSensitivity caseSensitivity = Qt::CaseInsensitive;
#else
    constexpr Qt::CaseSensitivity caseSensitivity = Qt::CaseSensitive;
#endif

    while (!currentPath.isEmpty())
    {
        if (currentPath.compare(rootPath, caseSensitivity) == 0)
            return {};

        const QString parentPath = QDir::cleanPath(QFileInfo(currentPath).absolutePath());

        if (parentPath.compare(rootPath, caseSensitivity) == 0)
        {
            const QFileInfo info(currentPath);
            return info.exists() && info.isDir() ? currentPath : QString();
        }

        if (parentPath.compare(currentPath, caseSensitivity) == 0)
            return {};

        currentPath = parentPath;
    }

    return {};
}

QString ContentSelectorView::ContentSelector::selectedNexusModDirectory() const
{
    const QString modDirectory = selectedManagedModDirectory();
    if (modDirectory.isEmpty())
        return {};

    const QDir dir(modDirectory);
    const QFileInfo openMwMetadata(dir.filePath(QStringLiteral("openmw-meta.ini")));
    const QFileInfo ametystMetadata(dir.filePath(QStringLiteral("meta.ini")));

    if (openMwMetadata.isFile() || ametystMetadata.isFile())
        return modDirectory;

    return {};
}

QString ContentSelectorView::ContentSelector::selectedConflictDirectoryPath() const
{
    const QModelIndexList selectedIndexes
        = ui->addonView->selectionModel()->selectedRows(ContentSelectorModel::ContentModel::Column_FileName);

    if (selectedIndexes.size() != 1)
        return {};

    const QModelIndex sourceIndex = mAddonProxyModel->mapToSource(selectedIndexes.constFirst());
    const ContentSelectorModel::EsmFile* file = mContentModel->item(sourceIndex.row());
    if (!file || file->conflictCount() <= 0 || file->filePath().isEmpty())
        return {};

    if (file->isAssetDirectory())
        return QDir::cleanPath(QFileInfo(file->filePath()).absoluteFilePath());

    return QDir::cleanPath(QFileInfo(file->filePath()).absolutePath());
}

void ContentSelectorView::ContentSelector::slotShowContextMenu(const QPoint& pos)
{
    if (mBrowseModFilesAction)
        mBrowseModFilesAction->setEnabled(!selectedManagedModDirectory().isEmpty());

    if (mShowAssetConflictsAction)
        mShowAssetConflictsAction->setEnabled(!selectedConflictDirectoryPath().isEmpty());

    const QString nexusModDirectory = selectedNexusModDirectory();
    if (mShowNexusModAction)
    {
        mShowNexusModAction->setVisible(!nexusModDirectory.isEmpty());
        mShowNexusModAction->setEnabled(!nexusModDirectory.isEmpty());
    }

    if (mDeleteModAction)
        mDeleteModAction->setEnabled(!selectedManagedModDirectory().isEmpty());

    QPoint globalPos = ui->addonView->viewport()->mapToGlobal(pos);
    mContextMenu->exec(globalPos);
}

void ContentSelectorView::ContentSelector::slotBrowseModFiles()
{
    const QString path = selectedManagedModDirectory();
    if (!path.isEmpty())
        QDesktopServices::openUrl(QUrl::fromLocalFile(path));
}

void ContentSelectorView::ContentSelector::slotShowNexusMod()
{
    const QString path = selectedNexusModDirectory();
    if (!path.isEmpty())
        emit signalShowNexusModRequested(path);
}

void ContentSelectorView::ContentSelector::slotDeleteMod()
{
    const QString path = selectedManagedModDirectory();
    if (!path.isEmpty())
        emit signalDeleteModRequested(path);
}

void ContentSelectorView::ContentSelector::slotShowAssetConflicts()
{
    const QString path = selectedConflictDirectoryPath();
    if (!path.isEmpty())
        emit signalShowAssetConflicts(path);
}

void ContentSelectorView::ContentSelector::setCheckStateForMultiSelectedItems(Qt::CheckState checkState)
{
    const QModelIndexList selectedIndexes
        = ui->addonView->selectionModel()->selectedRows(ContentSelectorModel::ContentModel::Column_FileName);

    QProgressDialog progressDialog("Updating content selection", {}, 0, static_cast<int>(selectedIndexes.size()));
    progressDialog.setWindowModality(Qt::WindowModal);
    progressDialog.setValue(0);

    for (qsizetype i = 0, n = selectedIndexes.size(); i < n; ++i)
    {
        const QModelIndex sourceIndex = mAddonProxyModel->mapToSource(selectedIndexes[i]);

        if (mContentModel->data(sourceIndex, Qt::CheckStateRole).toInt() != checkState)
            mContentModel->setData(sourceIndex, checkState, Qt::CheckStateRole);

        progressDialog.setValue(static_cast<int>(i + 1));
    }
}

void ContentSelectorView::ContentSelector::slotUncheckMultiSelectedItems()
{
    setCheckStateForMultiSelectedItems(Qt::Unchecked);
}

void ContentSelectorView::ContentSelector::setGroundcoverForSelectedItems(bool enabled)
{
    bool changed = false;

    const QModelIndexList selectedIndexes
        = ui->addonView->selectionModel()->selectedRows(ContentSelectorModel::ContentModel::Column_FileName);

    for (const QModelIndex& proxyIndex : selectedIndexes)
    {
        const QModelIndex sourceIndex = mAddonProxyModel->mapToSource(proxyIndex);
        const ContentSelectorModel::EsmFile* file = mContentModel->item(sourceIndex.row());
        changed = mContentModel->setGroundcover(file, enabled) || changed;
    }

    if (changed)
        emit signalGroundcoverChanged(enabled);
}

void ContentSelectorView::ContentSelector::slotCheckMultiSelectedItems()
{
    setCheckStateForMultiSelectedItems(Qt::Checked);
}

void ContentSelectorView::ContentSelector::slotCopySelectedItemsPaths()
{
    QClipboard* clipboard = QApplication::clipboard();
    QStringList filepaths;
    for (const QModelIndex& index :
        ui->addonView->selectionModel()->selectedRows(ContentSelectorModel::ContentModel::Column_FileName))
    {
        int row = mAddonProxyModel->mapToSource(index).row();
        const ContentSelectorModel::EsmFile* file = mContentModel->item(row);
        filepaths.push_back(file->filePath());
    }

    if (!filepaths.isEmpty())
    {
        clipboard->setText(filepaths.join("\n"));
    }
}

void ContentSelectorView::ContentSelector::slotSearchFilterTextChanged(const QString& newText)
{
    ui->addonView->setDragEnabled(newText.isEmpty());
}

void ContentSelectorView::ContentSelector::slotSortFiles()
{
    if (!mContentModel)
        return;

    // ContentModel already knows the master/dependency graph and keeps
    // built-in/non-user entries at the beginning. Reuse that native sorter
    // instead of maintaining a second load-order implementation here.
    mContentModel->sortFiles();
    ui->addonView->selectionModel()->clearSelection();

    emit signalLoadOrderChanged();
}

void ContentSelectorView::ContentSelector::slotRowsMoved()
{
    ui->addonView->selectionModel()->clearSelection();
}
