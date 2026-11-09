-- RoadsideStand
-- Builds the fill type categories the roadside stand's triggers use:
--   ROADSIDESTAND_CROPS: harvested field crops (base game, map and mods), windrows (grass, hay, straw,
--                        alfalfa, clover, ... incl. map/mod ones) + wood chips
--   ROADSIDESTAND_BALES: every bale fill type
--   ROADSIDESTAND_PALLETS: the few pallet goods nothing else buys (rope)
-- Nothing else (milk, products, fuel, inputs, ...) is accepted.

RoadsideStand = {}
RoadsideStand.CROPS_CATEGORY = "ROADSIDESTAND_CROPS"
RoadsideStand.BALES_CATEGORY = "ROADSIDESTAND_BALES"
RoadsideStand.PALLETS_CATEGORY = "ROADSIDESTAND_PALLETS"
-- Pallet goods sold through the pallet trigger
RoadsideStand.PALLET_FILLTYPES = {"ROPE"}
-- Accepted by name when present (map/mod fill types, e.g. NF Marsch / Fed packs):
-- flax (LINSEED) and its windrow, hemp and its windrow, legume straw (SOYBEANSTRAW)
RoadsideStand.EXTRA_CROP_FILLTYPES = {"WOODCHIPS", "LINSEED", "FLAX_WINDROW", "HEMP", "HEMP_WINDROW", "SOYBEANSTRAW"}
-- Fill type categories whose members are all windrows
RoadsideStand.WINDROW_CATEGORIES = {"WINDROW"}
-- Converters that turn a crop into a windrow (mowing) or a windrow into another windrow (tedding)
RoadsideStand.WINDROW_FRUIT_CONVERTERS = {"MOWER"}
RoadsideStand.WINDROW_FILL_CONVERTERS = {"TEDDER"}
-- Fill type name patterns that are always accepted (alfalfa/clover aren't in the base game, maps and mods add them)
RoadsideStand.WINDROW_NAME_PATTERNS = {"WINDROW", "ALFALFA", "CLOVER"}

local function isSellable(fillType)
    return fillType ~= nil and fillType.index ~= FillType.UNKNOWN and fillType.pricePerLiter ~= nil and fillType.pricePerLiter > 0
end

local function addConverterTargets(converterData, addFillType)
    if converterData == nil then
        return
    end
    for _, data in pairs(converterData) do
        if type(data) == "table" then
            addFillType(data.targetFillTypeIndex)
        end
    end
end

function RoadsideStand.updateCategories()
    local fillTypeManager = g_fillTypeManager
    local cropsCategory = fillTypeManager:addFillTypeCategory(RoadsideStand.CROPS_CATEGORY, false)
    local balesCategory = fillTypeManager:addFillTypeCategory(RoadsideStand.BALES_CATEGORY, false)
    local palletsCategory = fillTypeManager:addFillTypeCategory(RoadsideStand.PALLETS_CATEGORY, false)
    if cropsCategory == nil or balesCategory == nil or palletsCategory == nil then
        Logging.error("[RoadsideStand] Could not create fill type categories")
        return
    end

    local crops = {}
    local numCrops = 0
    local function addCrop(fillTypeIndex)
        if fillTypeIndex ~= nil and not crops[fillTypeIndex] and isSellable(fillTypeManager:getFillTypeByIndex(fillTypeIndex)) then
            fillTypeManager:addFillTypeToCategory(fillTypeIndex, cropsCategory)
            crops[fillTypeIndex] = true
            numCrops = numCrops + 1
        end
    end

    if g_fruitTypeManager ~= nil then
        for _, fruitType in ipairs(g_fruitTypeManager:getFruitTypes()) do
            addCrop(g_fruitTypeManager:getFillTypeIndexByFruitTypeIndex(fruitType.index))
            if g_fruitTypeManager.getWindrowFillTypeIndexByFruitTypeIndex ~= nil then
                addCrop(g_fruitTypeManager:getWindrowFillTypeIndexByFruitTypeIndex(fruitType.index))
            end
        end

        if g_fruitTypeManager.getConverterDataByName ~= nil then
            for _, name in ipairs(RoadsideStand.WINDROW_FRUIT_CONVERTERS) do
                addConverterTargets(g_fruitTypeManager:getConverterDataByName(name), addCrop)
            end
        end
    end

    if fillTypeManager.getConverterDataByName ~= nil then
        for _, name in ipairs(RoadsideStand.WINDROW_FILL_CONVERTERS) do
            addConverterTargets(fillTypeManager:getConverterDataByName(name), addCrop)
        end
    end

    if fillTypeManager.getFillTypesByCategoryNames ~= nil then
        for _, fillTypeIndex in ipairs(fillTypeManager:getFillTypesByCategoryNames(table.concat(RoadsideStand.WINDROW_CATEGORIES, " "), nil)) do
            addCrop(fillTypeIndex)
        end
    end

    for _, name in ipairs(RoadsideStand.EXTRA_CROP_FILLTYPES) do
        local fillType = fillTypeManager:getFillTypeByName(name)
        if fillType ~= nil then
            addCrop(fillType.index)
        end
    end

    local numBales = 0
    for _, fillType in ipairs(fillTypeManager:getFillTypes()) do
        if fillType.name ~= nil then
            for _, pattern in ipairs(RoadsideStand.WINDROW_NAME_PATTERNS) do
                if string.find(fillType.name, pattern, 1, true) ~= nil then
                    addCrop(fillType.index)
                    break
                end
            end
        end

        if fillType.isBaleType and isSellable(fillType) then
            fillTypeManager:addFillTypeToCategory(fillType.index, balesCategory)
            numBales = numBales + 1
        end
    end

    local numPallets = 0
    for _, name in ipairs(RoadsideStand.PALLET_FILLTYPES) do
        local fillType = fillTypeManager:getFillTypeByName(name)
        if isSellable(fillType) then
            fillTypeManager:addFillTypeToCategory(fillType.index, palletsCategory)
            numPallets = numPallets + 1
        end
    end

    Logging.info("[RoadsideStand] Roadside stand accepts %d crop/windrow, %d bale and %d pallet fill types", numCrops, numBales, numPallets)
end

-- Fill types and fruit types are loaded in several steps (base game, map, mods) whose order isn't
-- guaranteed, so rebuild the categories after each one. Adding to a category is idempotent.
-- overwrittenFunction (not appendedFunction) so the original return values are passed through.
local function rebuildAfter(class, funcName)
    class[funcName] = Utils.overwrittenFunction(class[funcName], function(self, superFunc, ...)
        local result = superFunc(self, ...)
        RoadsideStand.updateCategories()
        return result
    end)
end

rebuildAfter(FillTypeManager, "loadMapData")
rebuildAfter(FillTypeManager, "loadModFillTypes")
rebuildAfter(FruitTypeManager, "loadMapData")
