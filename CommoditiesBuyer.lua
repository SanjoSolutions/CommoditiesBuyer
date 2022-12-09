local AddOn = {}

function AddOn.buy(itemID, quantity, maximumUnitPrice)
  Coroutine.runAsCoroutine(function()
    AuctionHouseFrame.CommoditiesBuyFrame.BuyDisplay.BuyButton:Disable()
    C_AuctionHouse.StartCommoditiesPurchase(itemID, quantity)
    local _, event, unitPrice, totalPrice = Events.waitForOneOfEvents({ 'COMMODITY_PRICE_UPDATED', 'COMMODITY_PRICE_UNAVAILABLE' })
    if event == 'COMMODITY_PRICE_UPDATED' then
      if unitPrice <= maximumUnitPrice then
        C_AuctionHouse.ConfirmCommoditiesPurchase(itemID, quantity)
        local _, event = Events.waitForOneOfEvents({ 'COMMODITY_PURCHASE_SUCCEEDED', 'COMMODITY_PURCHASE_FAILED' })
        if event == 'COMMODITY_PURCHASE_SUCCEEDED' then
          AuctionHouseFrame.CommoditiesBuyFrame.BuyDisplay.BuyButton:Enable()
          return
        elseif event == 'COMMODITY_PURCHASE_FAILED' then
          print('Purchase failed.')
          AuctionHouseFrame.CommoditiesBuyFrame.BuyDisplay.BuyButton:Enable()
        end
      else
        print('Purchase failed. The unit price that the items can be purchased with is higher than the maximum unit price.')
        AuctionHouseFrame.CommoditiesBuyFrame.BuyDisplay.BuyButton:Enable()
      end
    elseif event == 'COMMODITY_PRICE_UNAVAILABLE' then
      print('Purchase failed. Maybe the purchase quantity is higher than number of items available in the auction house.')
      AuctionHouseFrame.CommoditiesBuyFrame.BuyDisplay.BuyButton:Enable()
    end
  end)
end

local isAuctionHousePatched = false

-- TODO: Handle button enabling when player changes AH page?
local function onEvent(self, event, ...)
  if event == 'ADDON_LOADED' then
    AddOn.onAddonLoaded(...)
  elseif event == 'AUCTION_HOUSE_SHOW' then
    AddOn.patchAuctionHouse()
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
    AuctionHouseFrame.CommoditiesBuyFrame.ItemList:SetSelectionCallback(function (searchResultInfo)
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
