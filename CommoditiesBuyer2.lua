local AddOn = {}

local isThrottledSystemReady = true
local button
local thread
local remainingQuantity = nil

function AddOn.buy(itemID, quantity, maximumUnitPrice)
  thread = coroutine.create(function()
    remainingQuantity = quantity

    AuctionHouseFrame.CommoditiesBuyFrame.BuyDisplay.BuyButton:Disable()

    while remainingQuantity >= 1 do
      AddOn.sendSearchQuery(
        {
          -- itemLevel = , -- TODO: Is this required?
          itemSuffix = 0,
          itemID = itemID,
          battlePetSpeciesID = 0
        },
        {
          {
            sortOrder = Enum.AuctionHouseSortOrder.Price,
            reverseSort = false
          }
        },
        false
      )
      local numberOfCommoditySearchResults = C_AuctionHouse.GetNumCommoditySearchResults(itemID)
      local result = C_AuctionHouse.GetCommoditySearchResultInfo(itemID, 1)
      if result and result.itemID == itemID then
        local unitPrice = result.unitPrice
        local quantity = math.min(result.quantity, remainingQuantity)
        if unitPrice <= maximumUnitPrice then
          AddOn.showItemToBuyOut(
            {
              itemID = itemID,
              price = unitPrice,
              quantity = quantity
            },
            maximumUnitPrice
          )
        end
      end
    end
  end)
  Coroutine.resumeWithShowingError(thread)
end

function AddOn.showItemToBuyOut(buyoutItem, maximumUnitPrice)
  local itemIdentifier
  if buyoutItem.itemLink then
    itemIdentifier = buyoutItem.itemLink
  else
    itemIdentifier = select(2, GetItemInfo(buyoutItem.itemID))
  end
  local text
  if buyoutItem.isBid then
    text = 'Bidding on'
    button:SetText('Bid')
  else
    text = 'Buying'
    button:SetText('Buy')
  end
  print(text .. ' ' .. buyoutItem.quantity .. ' x ' .. itemIdentifier .. ' (buy price: ' .. GetCoinTextureString(buyoutItem.price) .. ', profit: ' .. GetCoinTextureString(buyoutItem.profit) .. ')')
  button:Show()
  coroutine.yield()
  AddOn.buyOut(buyoutItem, maximumUnitPrice)
end

function AddOn.sendSearchQuery(itemKey, sorts, separateOwnerItems, minLevelFilter, maxLevelFilter)
  local item = Item:CreateFromItemID(itemKey.itemID)
  AddOn.waitForItemToLoad(item)
  if not isThrottledSystemReady then
    AddOn.waitForThrottledSystemReady()
  end
  local wasSuccessful
  repeat
    C_AuctionHouse.SendSearchQuery(itemKey, sorts, separateOwnerItems, minLevelFilter, maxLevelFilter)
    wasSuccessful = Events.waitForEventCondition('COMMODITY_SEARCH_RESULTS_UPDATED', function(self, event, itemID)
      return itemID == itemKey.itemID
    end, 1)
  until wasSuccessful
end

function AddOn.buyOut(buyoutItem, maximumUnitPrice)
  button:Hide()

  local itemID = buyoutItem.itemID
  local quantity = buyoutItem.quantity
  C_AuctionHouse.StartCommoditiesPurchase(itemID, quantity)
  local _, event, unitPrice, totalPrice = Events.waitForOneOfEvents({ 'COMMODITY_PRICE_UPDATED', 'COMMODITY_PRICE_UNAVAILABLE' })
  if event == 'COMMODITY_PRICE_UPDATED' then
    if unitPrice <= maximumUnitPrice then
      C_AuctionHouse.ConfirmCommoditiesPurchase(itemID, quantity)
      local _, event = Events.waitForOneOfEvents({ 'COMMODITY_PURCHASE_SUCCEEDED', 'COMMODITY_PURCHASE_FAILED' })
      if event == 'COMMODITY_PURCHASE_SUCCEEDED' then
        remainingQuantity = math.max(remainingQuantity - quantity, 0)
      end
    end
  end
end

function AddOn.waitForItemToLoad(item)
  if not item:IsItemDataCached() then
    local thread = coroutine.running()

    item:ContinueOnItemLoad(function()
      Coroutine.resumeWithShowingError(thread)
    end)

    coroutine.yield()
  end
end

function AddOn.waitForThrottledSystemReady()
  Events.waitForEvent('AUCTION_HOUSE_THROTTLED_SYSTEM_READY')
end

function AddOn.onAuctionHouseThrottledMessageSent()
  isThrottledSystemReady = false
end

local isAuctionHousePatched = false

-- TODO: Handle button enabling when player changes AH page?
local function onEvent(self, event, ...)
  if event == 'ADDON_LOADED' then
    AddOn.onAddonLoaded(...)
  elseif event == 'AUCTION_HOUSE_SHOW' then
    AddOn.patchAuctionHouse()
  elseif event == 'AUCTION_HOUSE_THROTTLED_MESSAGE_SENT' then
    AddOn.onAuctionHouseThrottledMessageSent(...)
  end
end

function AddOn.onAddonLoaded(name)
  if name == 'CommoditiesBuyer' then
    AddOn.initializeSavedVariables()
  end
end

function AddOn.initializeSavedVariables()
  if not CommoditiesBuyerMaximumUnitPrices then
    CommoditiesBuyerMaximumUnitPrices = {}
  end
end

function AddOn.patchAuctionHouse()
  if not isAuctionHousePatched then
    local maximumPrice

    AuctionHouseFrame.CommoditiesBuyFrame.BuyDisplay.BuyButton:SetScript('OnClick', function()
      local itemID = AuctionHouseFrame.CommoditiesBuyFrame.BuyDisplay:GetItemID()
      local quantity = AuctionHouseFrame.CommoditiesBuyFrame.BuyDisplay:GetQuantitySelected()
      local maximumUnitPrice = maximumPrice:GetAmount()
      AddOn.buy(itemID, quantity, maximumUnitPrice)
      PlaySound(SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON)
    end)

    maximumPrice = CreateFrame('Frame', nil, AuctionHouseFrame.CommoditiesBuyFrame.BuyDisplay,
      'AuctionHouseAlignedPriceInputFrameTemplate')
    maximumPrice.layoutIndex = 30
    maximumPrice.labelText = 'Maximum Unit Price'
    maximumPrice:SetLabel(maximumPrice.labelText)
    maximumPrice:SetOnValueChangedCallback(function()
      local itemID = AuctionHouseFrame.CommoditiesBuyFrame.BuyDisplay:GetItemID()
      local maximumUnitPrice = maximumPrice:GetAmount()
      CommoditiesBuyerMaximumUnitPrices[itemID] = maximumUnitPrice

      local totalPrice = AddOn.calculateTotalPrice()
      AuctionHouseFrame.CommoditiesBuyFrame.BuyDisplay.TotalPrice:SetAmount(totalPrice)
    end)

    hooksecurefunc(AuctionHouseFrame.CommoditiesBuyFrame.BuyDisplay.TotalPrice, 'SetAmount', function(self, totalPrice)
      local totalPrice2 = AddOn.calculateTotalPrice()
      if totalPrice2 ~= totalPrice then
        AuctionHouseFrame.CommoditiesBuyFrame.BuyDisplay.TotalPrice:SetAmount(totalPrice2)
      end
    end)

    hooksecurefunc(AuctionHouseFrame.CommoditiesBuyFrame.BuyDisplay, 'SetItemIDAndPrice', function(self)
      local itemID = AuctionHouseFrame.CommoditiesBuyFrame.BuyDisplay:GetItemID()
      local maximumUnitPrice = CommoditiesBuyerMaximumUnitPrices[itemID]
      if maximumUnitPrice then
        maximumPrice:SetAmount(maximumUnitPrice)
      else

        maximumPrice:Clear()
      end
    end)

    function AddOn.calculateTotalPrice()
      local quantity = AuctionHouseFrame.CommoditiesBuyFrame.BuyDisplay:GetQuantitySelected()
      local maximumUnitPrice = maximumPrice:GetAmount()
      local totalPrice = quantity * maximumUnitPrice
      return totalPrice
    end

    AuctionHouseFrame.CommoditiesBuyFrame.BuyDisplay.UnitPrice:Hide()
    AuctionHouseFrame.CommoditiesBuyFrame.BuyDisplay.TotalPrice.labelText = 'Maximum Total Price'
    AuctionHouseFrame.CommoditiesBuyFrame.BuyDisplay.TotalPrice:SetLabel(AuctionHouseFrame.CommoditiesBuyFrame.BuyDisplay.TotalPrice.labelText)

    local originalCallback = AuctionHouseFrame.CommoditiesBuyFrame.ItemList.selectionCallback
    AuctionHouseFrame.CommoditiesBuyFrame.ItemList:SetSelectionCallback(function(searchResultInfo)
      maximumPrice:SetAmount(searchResultInfo.unitPrice)
      return originalCallback(searchResultInfo)
    end)

    isAuctionHousePatched = true
  end
end

local frame = CreateFrame('Frame')
frame:SetScript('OnEvent', onEvent)
frame:RegisterEvent('ADDON_LOADED')
frame:RegisterEvent('AUCTION_HOUSE_SHOW')
frame:RegisterEvent('AUCTION_HOUSE_THROTTLED_MESSAGE_SENT')

button = CreateFrame('Button', nil, UIParent, 'UIPanelButtonNoTooltipTemplate')
button:SetPoint('CENTER', 0, 0)
button:SetSize(300, 60)
button:SetText('Buy')
button:SetScript('OnClick', function()
  Coroutine.resumeWithShowingError(thread)
end)
button:Hide()
