-- Project: PonyTiled a Corona Tiled Map Loader
--
-- Loads LUA saved map files from Tiled http://www.mapeditor.org/

local M = {}
local physics = require "physics"

local FlippedHorizontallyFlag   = 0x80000000
local FlippedVerticallyFlag     = 0x40000000
local FlippedDiagonallyFlag     = 0x20000000

local function hasbit(x, p) return x % (p + p) >= p end
local function setbit(x, p) return hasbit(x, p) and x or x + p end
local function clearbit(x, p) return hasbit(x, p) and x - p or x end

local function inherit(image, properties)
  for k,v in pairs(properties) do
    image[k] = v
  end
  return image
end

local function centerAnchor(image)
  if image.contentBounds then 
    local bounds = image.contentBounds
    local actualCenterX, actualCenterY =  (bounds.xMin + bounds.xMax)/2 , (bounds.yMin + bounds.yMax)/2
    image.anchorX, image.anchorY = 0.5, 0.5  
    image.x = actualCenterX
    image.y = actualCenterY 
  end
end

local function decodeTiledColor(hex)
  hex = hex or "#FF888888"
  hex = hex:gsub("#","")
  local function hexToFloat(part)
    return tonumber("0x".. part or "00") / 255
  end
  local a, r, g, b =  hexToFloat(hex:sub(1,2)), hexToFloat(hex:sub(3,4)), hexToFloat(hex:sub(5,6)) , hexToFloat(hex:sub(7,8)) 
  return r,g,b,a
end

function M.new(data)
  local map = display.newGroup()  

  local layers = data.layers
  local tilesets = data.tilesets
  local width, height = data.width * data.tilewidth, data.height * data.tileheight
  local sheets = {}

  local function loadTileset(num)
    local tileset = tilesets[num]
    local tsiw, tsih = tileset.imagewidth, tileset.imageheight
    local margin, spacing = tileset.margin, tileset.spacing
    local w, h = tileset.tilewidth, tileset.tileheight
    local gid = 0
    
    local options = {
      frames = {},
      sheetContentWidth =  tsiw,
      sheetContentHeight = tsih,
    }

    local frames = options.frames
    local tsh = math.ceil((tsih - margin*2 - spacing) / (h + spacing))
    local tsw = math.ceil((tsiw - margin*2 - spacing) / (w + spacing))

    for j=1, tsh do
      for i=1, tsw do
        local element = {
          x = (i-1)*(w + spacing) + margin,
          y = (j-1)*(h + spacing) + margin,
          width = w,
          height = h,
        }
        gid = gid + 1
        table.insert( frames, gid, element )
      end
    end
    print ("LOADED:", tileset.image)
    return graphics.newImageSheet(tileset.image, options )
  end

  local function gidLookup(gid)
    -- flipping merged from code by Sergey Lerg    
    local flip = {}
    flip.x = hasbit(gid, FlippedHorizontallyFlag)
    flip.y = hasbit(gid, FlippedVerticallyFlag)          
    flip.xy = hasbit(gid, FlippedDiagonallyFlag) 
    gid = clearbit(gid, FlippedHorizontallyFlag)
    gid = clearbit(gid, FlippedVerticallyFlag)
    gid = clearbit(gid, FlippedDiagonallyFlag)
    -- turn a gid into a filename or sheet/frame 
    for i = 1, #tilesets do
      local tileset = tilesets[i]
      local firstgid = tileset.firstgid
      local lastgid = firstgid + tileset.tilecount 
      if gid >= firstgid and gid <= lastgid then
        if tileset.image then -- spritesheet
          if not sheets[i] then 
            sheets[i] = loadTileset(i)
          end
          return gid - firstgid + 1, flip, sheets[i]
        else -- collection of images
          for k,v in pairs(tileset.tiles) do
            if (v.id or tonumber(k)) == gid - firstgid then
              return v.image, flip -- may need updating with documents directory
            end
          end
        end
      end
    end
    return false
  end

  for i = 1, #layers do
    local layer = layers[i]
    layer.properties = layer.properties or {} -- make sure we have a properties table
    local objectGroup = display.newGroup()    
    if layer.type == "tilelayer" then
      if layer.compression or layer.encoding then
        print ("ERROR: Tile layer encoding/compression not supported. Choose CSV or XML in map options.")
      end
      local item = 0
      for ty=0, data.height-1 do
        for tx=0, data.width-1 do
          item = (ty * data.width) + tx
          local tileNumber = layer.data[item] or 0
          local gid, flip, sheet = gidLookup(tileNumber)
          if gid then
            local image = sheet and display.newImage(objectGroup, sheet, gid, 0, 0) or display.newImage(objectGroup, gid, 0, 0)
            image.anchorX, image.anchorY = 0,1
            image.x, image.y = (tx-1) * data.tilewidth, (ty+1) * data.tileheight
            centerAnchor(image)
            -- flip it
            if flip.xy then
              print("WARNING: Unsupported Tiled rotation x,y in tile ", tx,ty)
            else
              if flip.x then
                image.xScale = -1
              end
              if flip.y then
                image.yScale = -1
              end
            end          
            -- apply custom properties
            image = inherit(image, layer.properties)
          end
        end
      end
    elseif layer.type == "objectgroup" then
      for j = 1, #layer.objects do
        local object = layer.objects[j]
        object.properties = object.properties or {} -- make sure we have a properties table
        if object.gid then
          local gid, flip, sheet = gidLookup(object.gid)
          if gid then
            local image = sheet and display.newImageRect(objectGroup, sheet, gid, object.width, object.height) or display.newImageRect(objectGroup, gid, object.width, object.height)
            -- name and type
            image.name = object.name
            image.type = object.type        
            -- apply base properties
            image.anchorX, image.anchorY = 0, 1
            image.x, image.y = object.x, object.y
            image.rotation = object.rotation
            image.isVisible = object.visible
            centerAnchor(image)
            -- flip it
            if flip.xy then
              print("WARNING: Unsupported Tiled rotation x,y in ", object.name)
            else
              if flip.x then
                image.xScale = -1
              end
              if flip.y then
                image.yScale = -1
              end
            end          
            -- simple phyics
            if object.properties.bodyType then
              physics.addBody(image, object.properties.bodyType, object.properties)
            end          
            -- apply custom properties
            image = inherit(image, object.properties)
            image = inherit(image, layer.properties)
          end
        else -- if all else fails make a simple rect
          local rect = display.newRect(0, 0, object.width, object.height)
          rect.anchorX, rect.anchorY = 0, 0
          rect.x, rect.y = object.x, object.y
          centerAnchor(rect)
          -- apply custom properties
          rect = inherit(rect, object.properties)
          rect = inherit(rect, layer.properties)          
          if rect.fillColor then rect:setFillColor(decodeTiledColor(rect.fillColor)) end
          if rect.strokeColor then rect:setStrokeColor(decodeTiledColor(rect.strokeColor)) end                
          objectGroup:insert(rect)
        end
      end
    end
    objectGroup.name = layer.name
    objectGroup.isVisible = layer.visible
    objectGroup.alpha = layer.opacity
    map:insert(objectGroup)  
  end

  function map:extend(...)
    local plugins = arg or {}
    -- each custom object above has its own ponywolf.plugin module
    for t = 1, #plugins do 
      -- load each module based on type
      local plugin = require ("com.ponywolf.plugins." .. plugins[t])
      -- find each type of tiled object
      local images = map:listTypes(plugins[t])
      if images then 
        -- do we have at least one?
        for i = 1, #images do
          -- extend the display object with its own custom code
          images[i] = plugin.new(images[i])
        end
      end  
    end
  end

-- return first display object with name
  function map:findObject(name)
    for layers = self.numChildren,1,-1 do
      local layer = self[layers]
      if layer.numChildren then
        for i = layer.numChildren,1,-1 do
          if layer[i].name == name then
            return layer[i]
          end
        end
      end
    end
    return false
  end

-- return all display objects with type
  function map:listTypes(...)
    local objects = {}
    for layers = self.numChildren,1,-1 do
      local layer = self[layers]
      if layer.numChildren then
        for i = layer.numChildren,1,-1 do
          for j = 1, #arg do 
            if arg[j]==nil or layer[i].type == arg[j] then
              objects[#objects+1] = layer[i]
            end
          end
        end
      end
    end
    return objects
  end

-- add helpful values to the map itself
  map.designedWidth, map.designedHeight = width, height
  return map
end

return M