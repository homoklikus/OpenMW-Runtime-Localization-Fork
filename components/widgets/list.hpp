#ifndef OPENMW_COMPONENTS_WIDGETS_LIST_HPP
#define OPENMW_COMPONENTS_WIDGETS_LIST_HPP

#include <MyGUI_ScrollView.h>

namespace Gui
{
    /**
     * \brief a very simple list widget that supports word-wrapping entries
     * \note if the width or height of the list changes, you must call adjustSize() method
     */
    class MWList : public MyGUI::Widget
    {
        MYGUI_RTTI_DERIVED(MWList)
    public:
        MWList();

        typedef MyGUI::delegates::MultiDelegate<const std::string&, int> EventHandle_StringInt;
        typedef MyGUI::delegates::MultiDelegate<MyGUI::Widget*> EventHandle_Widget;

        /**
         * Event: Item selected with the mouse.
         * signature: void method(std::string eventName, int index)
         */
        EventHandle_StringInt eventItemSelected;

        /**
         * Event: Item selected with the mouse.
         * signature: void method(MyGUI::Widget* sender)
         */
        EventHandle_Widget eventWidgetSelected;

        /**
         * Call after the size of the list changed, or items were inserted/removed
         */
        void adjustSize();

        void sort();
        void addItem(std::string_view name, int verticalPadding = 0);
        // Adds an item with a display label separated from the value emitted on selection.
        void addItem(std::string_view name, std::string_view eventName, int verticalPadding = 0);
        void addSeparator(); ///< add a seperator between the current and the next item.
        void removeItem(const std::string& name);
        size_t getItemCount();
        const std::string& getItemNameAt(size_t at); ///< \attention if there are separators, this method will return ""
                                                     ///< at the place where the separator is
        void clear();

        MyGUI::Button* getItemWidget(std::string_view name);
        ///< get widget for an item display name, useful to set up tooltip
        MyGUI::Button* getItemWidgetByEventName(std::string_view eventName);
        ///< get widget by the value emitted on selection

        void scrollToTop();
        void setViewOffset(int offset);

        void setPropertyOverride(std::string_view key, std::string_view value) override;

    protected:
        void initialiseOverride() override;

        void redraw(bool scrollbarShown = false);

        void onMouseWheelMoved(MyGUI::Widget* sender, int rel);
        void onItemSelected(MyGUI::Widget* sender);

    private:
        MyGUI::Button* getItemWidgetAt(size_t index);

        MyGUI::ScrollView* mScrollView;
        MyGUI::Widget* mClient;
        std::string mListItemSkin;

        struct ListItemData
        {
            std::string mName;
            std::string mEventName;
            int mVPadding;

            ListItemData(std::string_view name, std::string_view eventName, int verticalPadding)
                : mName(name)
                , mEventName(eventName)
                , mVPadding(verticalPadding)
            {
            }
        };
        std::vector<ListItemData> mItems;

        int mItemHeight; // height of all items
    };
}

#endif
