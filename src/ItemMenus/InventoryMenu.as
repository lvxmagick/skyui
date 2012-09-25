﻿import gfx.io.GameDelegate;
import Shared.GlobalFunc;
import gfx.ui.NavigationCode;
import gfx.ui.InputDetails;

import skyui.components.list.ListLayoutManager;
import skyui.components.list.TabularList;
import skyui.components.list.ListLayout;
import skyui.props.PropertyDataExtender;


class InventoryMenu extends ItemMenu
{
  /* PRIVATE VARIABLES */
  
	private var _bMenuClosing: Boolean = false;
	private var _bSwitchMenus: Boolean = false;

	private var _categoryListIconArt: Array;
	
	
  /* PROPERTIES */
  
	// @GFx
	// @Mysterious
	public var bPCControlsReady: Boolean = true;


  /* INITIALIZATION */

	public function InventoryMenu()
	{
		super();
		
		_categoryListIconArt = ["cat_favorites", "inv_all", "inv_weapons", "inv_armor",
							   "inv_potions", "inv_scrolls", "inv_food", "inv_ingredients",
							   "inv_books", "inv_keys", "inv_misc"];
		
		GameDelegate.addCallBack("AttemptEquip", this, "AttemptEquip");
		GameDelegate.addCallBack("DropItem", this, "DropItem");
		GameDelegate.addCallBack("AttemptChargeItem", this, "AttemptChargeItem");
		GameDelegate.addCallBack("ItemRotating", this, "ItemRotating");
	}
	
	// @override ItemMenu
	public function InitExtensions(): Void
	{		
		super.InitExtensions();

		GlobalFunc.AddReverseFunctions();
		
		inventoryLists.zoomButtonHolder.gotoAndStop(1);
	
		// Initialize menu-specific list components
		var categoryList: CategoryList = inventoryLists.categoryList;
		categoryList.iconArt = _categoryListIconArt;

		itemCard.addEventListener("itemPress", this, "onItemCardListPress");
	}

  /* PUBLIC FUNCTIONS */

	// @override ItemMenu
	public function setConfig(a_config: Object): Void
	{
		super.setConfig(a_config);
		
		skyui.util.Debug.log("Setting config");
		
		var itemList: TabularList = inventoryLists.itemList;
		itemList.addDataProcessor(new InventoryDataExtender());
		itemList.addDataProcessor(new PropertyDataExtender(a_config["Properties"], "itemProperties", "itemIcons", "itemCompoundProperties"));
		
		var layout: ListLayout = ListLayoutManager.createLayout(a_config["ListLayout"], "ItemListLayout");
		itemList.layout = layout;

		// Not 100% happy with doing this here, but has to do for now.
		if (inventoryLists.categoryList.selectedEntry)
			layout.changeFilterFlag(inventoryLists.categoryList.selectedEntry.flag);
	}

	// @GFx
	public function handleInput(details: InputDetails, pathToFocus: Array): Boolean
	{
		if (!bFadedIn)
			return true;
		
		var nextClip = pathToFocus.shift();
		if (nextClip.handleInput(details, pathToFocus))
			return true;
			
		if (GlobalFunc.IsKeyPressed(details)) {
			if (details.navEquivalent == NavigationCode.TAB) {
				startMenuFade();
				GameDelegate.call("CloseTweenMenu", []);
			} else if (!inventoryLists.itemList.disableInput) {
				// Gamepad back || ALT (default) || 'P'
				var bGamepadBackPressed = (details.navEquivalent == NavigationCode.GAMEPAD_BACK && details.code != 8);
				if (bGamepadBackPressed || (_tabToggleKey && details.code == _tabToggleKey) || details.code == 80)
					openMagicMenu(true);
			}
		}
		
		return true;
	}

	// @override ItemMenu
	public function onExitMenuRectClick(): Void
	{
		startMenuFade();
		GameDelegate.call("ShowTweenMenu", []);
	}

	public function onFadeCompletion(): Void
	{
		if (!_bMenuClosing)
			return;

		GameDelegate.call("CloseMenu", []);
		if (_bSwitchMenus) {
			GameDelegate.call("CloseTweenMenu",[]);
			skse.OpenMenu("MagicMenu");
		}
	}

	// @override ItemMenu
	public function onShowItemsList(event: Object): Void
	{
		super.onShowItemsList(event);
		
		if (event.index != -1)
			updateBottomBar(true);
	}

	public function onItemHighlightChange(event: Object): Void
	{
		super.onItemHighlightChange(event);
		
		if (event.index != -1)
			updateBottomBar(true);
			
	}

	// @override ItemMenu
	public function onHideItemsList(event: Object): Void
	{
		super.onHideItemsList(event);
		bottomBar.updatePerItemInfo({type:InventoryDefines.ICT_NONE});
		updateBottomBar(false);
	}

	// @override ItemMenu
	public function onItemSelect(event: Object): Void
	{
		if (event.entry.enabled && event.keyboardOrMouse != 0)
			GameDelegate.call("ItemSelect", []);
	}

	// @API
	public function AttemptEquip(a_slot: Number, a_bCheckOverList: Boolean): Void
	{
		var bCheckOverList = a_bCheckOverList != undefined ? a_bCheckOverList : true;
		if (shouldProcessItemsListInput(bCheckOverList) && confirmSelectedEntry())
			GameDelegate.call("ItemSelect", [a_slot]);
	}

	// @API
	public function DropItem(): Void
	{
		if (shouldProcessItemsListInput(false) && inventoryLists.itemList.selectedEntry != undefined) {
			if (inventoryLists.itemList.selectedEntry.count <= InventoryDefines.QUANTITY_MENU_COUNT_LIMIT)
				onQuantityMenuSelect({amount:1});
			else
				itemCard.ShowQuantityMenu(inventoryLists.itemList.selectedEntry.count);
		}
	}

	// @API
	public function AttemptChargeItem(): Void
	{
		if (inventoryLists.itemList.selectedIndex == -1)
			return;
		
		if (shouldProcessItemsListInput(false) && itemCard.itemInfo.charge != undefined && itemCard.itemInfo.charge < 100)
			GameDelegate.call("ShowSoulGemList", []);
	}

	// @override ItemMenu
	public function onQuantityMenuSelect(event: Object): Void
	{
		GameDelegate.call("ItemDrop", [event.amount]);
		
		// Bug Fix: ItemCard does not update when attempting to drop quest items through the quantity menu
		//   so let's request an update even though it may be redundant.
		GameDelegate.call("RequestItemCardInfo", [], this, "UpdateItemCardInfo");
	}


	public function onMouseRotationFastClick(aiMouseButton: Number): Void
	{
		GameDelegate.call("CheckForMouseEquip", [aiMouseButton], this, "AttemptEquip");
	}

	public function onItemCardListPress(event: Object): Void
	{
		GameDelegate.call("ItemCardListCallback", [event.index]);
	}

	// @override ItemMenu
	public function onItemCardSubMenuAction(event: Object): Void
	{
		super.onItemCardSubMenuAction(event);
		GameDelegate.call("QuantitySliderOpen", [event.opening]);
		
		if (event.menu == "list") {
			if (event.opening == true) {
				bottomBar.clearButtons();
				bottomBar.addButton({text: "$Select", controls: (_platform == 0 ? _acceptPCControls : _acceptGPControls)});
				bottomBar.addButton({text: "$Cancel", controls: (_platform == 0 ? _cancelPCControls : _cancelGPControls)});
				bottomBar.positionButtons();
			} else {
				GameDelegate.call("RequestItemCardInfo", [], this, "UpdateItemCardInfo");
				updateBottomBar(true);
			}
		}
	}

	// @override ItemMenu
	public function SetPlatform(a_platform: Number, a_bPS3Switch: Boolean): Void
	{
		inventoryLists.zoomButtonHolder.gotoAndStop(1);
		inventoryLists.zoomButtonHolder.ZoomButton._visible = a_platform != 0;
		inventoryLists.zoomButtonHolder.ZoomButton.SetPlatform(a_platform, a_bPS3Switch);
		
		super.SetPlatform(a_platform, a_bPS3Switch);
		
		updateBottomBar(false);
	}

	// @API
	public function ItemRotating(): Void
	{
		inventoryLists.zoomButtonHolder.PlayForward(inventoryLists.zoomButtonHolder._currentframe);
	}
	
	
  /* PRIVATE FUNCTIONS */
	
	private function openMagicMenu(a_bFade: Boolean): Void
	{
		if (a_bFade) {
			_bSwitchMenus = true;
			startMenuFade();
		} else {
			saveIndices();
			GameDelegate.call("CloseMenu",[]);
			GameDelegate.call("CloseTweenMenu",[]);
			skse.OpenMenu("MagicMenu");
		}
	}
	
	private function startMenuFade(): Void
	{
		inventoryLists.hidePanel();
		ToggleMenuFade();
		saveIndices();
		_bMenuClosing = true;
	}
	
	private function updateBottomBar(a_bSelected: Boolean): Void
	{
		bottomBar.clearButtons();
		
		if (a_bSelected) {
			bottomBar.addButton(getEquipButtonData(itemCard.itemInfo.type));
			bottomBar.addButton({text: "$Drop", controls: _xButtonControls});
			
			if (inventoryLists.itemList.selectedEntry.filterFlag & inventoryLists.categoryList.entryList[0].flag != 0)
				bottomBar.addButton({text: "$Unfavorite", controls: _yButtonControls});
			else
				bottomBar.addButton({text: "$Favorite", controls: _yButtonControls});
	
			if (itemCard.itemInfo.charge != undefined && itemCard.itemInfo.charge < 100)
				bottomBar.addButton({text: "$Charge", controls: _waitControls});
				
		} else {
			bottomBar.addButton({text: "$Exit", controls: (_platform == 0 ? _cancelPCControls : _cancelGPControls)});
			bottomBar.addButton({text: "$Search", controls: _searchControls});
			bottomBar.addButton({text: "$Magic", controls: _tabControls});
		}
		
		bottomBar.positionButtons();
	}
}