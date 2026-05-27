local Script = {}
local blockWhitelist = {}
local LogSys = {}
local PlrDataMgr = {}

-- 组件属性
Script.propertys = {
    VAR_CMP_ID = {
        type = Mini.String,
        default = "",
        displayName = "变量组件ID",
        sort = -1,
        tips = "用于存储数据的库（详情查看本项目README.md）",
    },
    LOG_CMP_ID = {
        type = Mini.String,
        default = "",
        displayName = "日志组件ID",
        sort = 0,
        tips = "用于输出信息的库（详情查看本项目README.md）",
    },
    EYE_HEIGHT = {
        type = Mini.Number,
        default = 1.6,
        displayName = "眼睛高度",
        sort = 1,
        tips = "摄像机或角色眼睛的默认高度",
    },
    MAX_DIST = {
        type = Mini.Number,
        default = 100,
        displayName = "最大距离",
        sort = 2,
        tips = "检测或计算的最大距离限制",
    },
    STEP_SIZE = {
        type = Mini.Number,
        default = 0.008,
        displayName = "步长大小",
        sort = 3,
        tips = "迭代或移动的步进步长",
        format = "%.5f",
    },
    LEG_RATIO = {
        type = Mini.Number,
        default = 0.32,
        displayName = "腿部比例",
        sort = 4,
        tips = "腿部在整体模型中的占比系数",
        format = "%.5f",
    },
    HEAD_RATIO = {
        type = Mini.Number,
        default = 0.58,
        displayName = "头部比例",
        sort = 5,
        tips = "头部在整体模型中的占比系数",
        format = "%.5f",
    },
    ARM_START_RATIO = {
        type = Mini.Number,
        default = 0.31,
        displayName = "手臂起始高度比例",
        sort = 6,
        tips = "手臂开始生成的相对高度比例",
        format = "%.5f",
    },
    ABDOMEN_MIN_RATIO = {
        type = Mini.Number,
        default = 0.34,
        displayName = "腹部起始比例",
        sort = 7,
        tips = "腹部区域的最小高度比例",
        format = "%.5f",
    },
    ABDOMEN_MAX_RATIO = {
        type = Mini.Number,
        default = 0.4,
        displayName = "腹部结束比例",
        sort = 8,
        tips = "腹部区域的最大高度比例",
        format = "%.5f",
    },
    LATERAL_COEFF_HIGH = {
        type = Mini.Number,
        default = 0.4,
        displayName = "高区域横向系数",
        sort = 9,
        tips = "手臂区域横向偏移系数（×半宽）",
        format = "%.5f",
    },
    LATERAL_COEFF_LOW = {
        type = Mini.Number,
        default = 0.5,
        displayName = "低区域横向系数",
        sort = 10,
        tips = "低高度区域横向偏移系数",
        format = "%.5f",
    },
    LATERAL_COEFF_EXTREME = {
        type = Mini.Number,
        default = 1.2,
        displayName = "极外侧横向系数",
        sort = 11,
        tips = "极外侧横向偏移系数",
        format = "%.5f",
    },
    EXPERIMENTAL_WHITELIST = {
        type = Mini.Bool,
        default = false,
        displayName = "启用实验性白名单",
        sort = 12,
        tips = "启用后可配置特定方块被枪械攻击时忽略碰撞，适用于穿透类武器（极其不推荐开启）",
    },
    BLOCK_PENETRATION = {
        type = Mini.Bool,
        default = false,
        displayName = "启用方块穿透",
        sort = 13,
        tips = "启用后射线碰到方块将不再停止",
    },
}

local _VAR_STRUCT = {
    DATA = {
        lastFireTime = 0,
        lastBlockNum = 0,
    },
}

--- 脚本入口
--- @return nil @无返回
function Script:OnStart()
    local obj = GetWorld()
    LogSys = obj:GetComponent(self.LOG_CMP_ID)
    PlrDataMgr = obj:GetComponent(self.VAR_CMP_ID)

    if not PlrDataMgr then
        LogSys:Error("未找到变量组件", "Script:OnStart")
        return
    end
    if not LogSys then
        LogSys:Error("未找到日志组件", "Script:OnStart")
        return
    end
    -- 该表内的方块 ID 将按次数被忽略，仅在实验性白名单功能开启时生效
    blockWhitelist = {}
    if self.whitelistEnabled then
        blockWhitelist = {
            -- 示例：[1] = 3, -- 方块 ID 1 忽略 3 次
            -- 添加需要忽略的方块 ID 及忽略次数
            [100] = 5,
        }
    end

    for k, v in pairs(_VAR_STRUCT) do
        local key = tostring(k)
        PlrDataMgr:registerStruct("limbSysCmp", key, _VAR_STRUCT[key]) -- 注册结构
    end

    self:AddTriggerEvent(TriggerEvent.PlayerAttackHit, self.onPlayerAttackHit)
    self:AddTriggerEvent(TriggerEvent.GameAnyPlayerEnterGame, self.onGameAnyPlayerEnterGame)
end

--- 获取视野内所有潜在目标（玩家+生物）
--- @param centerX number @视野中心X坐标
--- @param centerY number @视野中心Y坐标
--- @param centerZ number @视野中心Z坐标
--- @param radius number @视野半径
--- @param excludeUin number @排除的玩家UIN
--- @return table @所有潜在目标信息列表
function Script:getAllTargets(centerX, centerY, centerZ, radius, excludeUin)
    local targets = {}
    local allPlayers = World:GetAllPlayers(-1)
    for _, uin in ipairs(allPlayers) do
        if uin ~= excludeUin and Actor:IsExist(uin) then
            local footX, footY, footZ = Actor:GetPosition(uin)
            if footX then
                local dx = footX - centerX
                local dy = footY - centerY
                local dz = footZ - centerZ
                if dx * dx + dy * dy + dz * dz <= radius * radius then
                    table.insert(targets, { id = uin, type = "player" })
                end
            end
        end
    end
    local posBeg = { x = centerX - radius, y = centerY - radius, z = centerZ - radius }
    local posEnd = { x = centerX + radius, y = centerY + radius, z = centerZ + radius }
    local creatures = Area:GetAllCreaturesInAreaRange(posBeg, posEnd)
    if creatures then
        for _, mobId in ipairs(creatures) do
            if Actor:IsExist(mobId) then
                table.insert(targets, { id = mobId, type = "mob" })
            end
        end
    end
    return targets
end

--- 射线与轴对齐包围盒相交
--- @param origin table @射线起点坐标 {x, y, z}
--- @param dir table @射线方向向量 {x, y, z}
--- @param minX number @包围盒最小X坐标
--- @param minY number @包围盒最小Y坐标
--- @param minZ number @包围盒最小Z坐标
--- @param maxX number @包围盒最大X坐标
--- @param maxY number @包围盒最大Y坐标
--- @param maxZ number @包围盒最大Z坐标
--- @return number|nil @相交距离，如果没有相交则返回nil
function Script:rayIntersectAABB(origin, dir, minX, minY, minZ, maxX, maxY, maxZ)
    local max, min = math.max, math.min
    local t1 = (minX - origin.x) / dir.x
    local t2 = (maxX - origin.x) / dir.x
    local t3 = (minY - origin.y) / dir.y
    local t4 = (maxY - origin.y) / dir.y
    local t5 = (minZ - origin.z) / dir.z
    local t6 = (maxZ - origin.z) / dir.z
    local tmin = max(min(t1, t2), min(t3, t4), min(t5, t6))
    local tmax = min(max(t1, t2), max(t3, t4), max(t5, t6))
    if tmax < 0 or tmin > tmax then
        return nil
    end
    return tmin
end

--- 判断方块是否在白名单中（消耗次数）
--- @param blockId number @方块 ID
--- @return boolean @是否被忽略
function Script:isBlockWhitelisted(blockId)
    local count = blockWhitelist[blockId]
    return type(count) == "number" and count > 0
end

--- 只读判断方块是否在白名单中（不消耗次数）
--- @param blockId number @方块ID
--- @return boolean @是否在白名单中且剩余次数 > 0
function Script:isBlockWhitelistedReadOnly(blockId)
    local count = blockWhitelist[blockId]
    return type(count) == "number" and count > 0
end

--- 统计玩家准星方向上白名单方块的数量（不同方块，去重）
--- @param playerUin number @玩家UIN
--- @param maxDist number @最大检测距离
--- @return number @白名单方块数量（去重）
function Script:countWhitelistBlocksInSight(playerUin, maxDist)
    if not Actor:IsExist(playerUin) then
        return 0
    end

    local eyeX, eyeY, eyeZ = Actor:GetPosition(playerUin)
    if not eyeX then
        return 0
    end
    eyeY = eyeY + self.EYE_HEIGHT

    local dir = Player:GetAimDir(playerUin)
    local len = math.sqrt(dir.x * dir.x + dir.y * dir.y + dir.z * dir.z)
    if len <= 0.0001 then
        return 0
    end
    dir.x, dir.y, dir.z = dir.x / len, dir.y / len, dir.z / len

    local origin = { x = eyeX, y = eyeY, z = eyeZ }
    local x, y, z = origin.x, origin.y, origin.z
    local ix, iy, iz = math.floor(x), math.floor(y), math.floor(z)

    local stepX = dir.x > 0 and 1 or -1
    local stepY = dir.y > 0 and 1 or -1
    local stepZ = dir.z > 0 and 1 or -1

    local tDeltaX = dir.x ~= 0 and math.abs(1 / dir.x) or math.huge
    local tDeltaY = dir.y ~= 0 and math.abs(1 / dir.y) or math.huge
    local tDeltaZ = dir.z ~= 0 and math.abs(1 / dir.z) or math.huge

    local nextBoundaryX = ix + (stepX > 0 and 1 or 0)
    local nextBoundaryY = iy + (stepY > 0 and 1 or 0)
    local nextBoundaryZ = iz + (stepZ > 0 and 1 or 0)

    local tMaxX = dir.x ~= 0 and ((nextBoundaryX - x) / dir.x) or math.huge
    local tMaxY = dir.y ~= 0 and ((nextBoundaryY - y) / dir.y) or math.huge
    local tMaxZ = dir.z ~= 0 and ((nextBoundaryZ - z) / dir.z) or math.huge

    local whitelistBlocks = {} -- 用于去重，key = "x,y,z"
    local t = 0
    while t <= maxDist do
        local blockId = Block:GetBlockID(ix + 0.5, iy + 0.5, iz + 0.5)
        if blockId and blockId ~= 0 and (self:isBlockWhitelistedReadOnly(blockId) and self.whitelistEnabled) then
            local key = string.format("%d,%d,%d", ix, iy, iz)
            whitelistBlocks[key] = true
        end

        if tMaxX < tMaxY then
            if tMaxX < tMaxZ then
                ix = ix + stepX
                t = tMaxX
                tMaxX = tMaxX + tDeltaX
            else
                iz = iz + stepZ
                t = tMaxZ
                tMaxZ = tMaxZ + tDeltaZ
            end
        else
            if tMaxY < tMaxZ then
                iy = iy + stepY
                t = tMaxY
                tMaxY = tMaxY + tDeltaY
            else
                iz = iz + stepZ
                t = tMaxZ
                tMaxZ = tMaxZ + tDeltaZ
            end
        end
    end

    local count = 0
    for _ in pairs(whitelistBlocks) do
        count = count + 1
    end

    local maxIgnoreCount = 0
    for _, ignoreCount in pairs(blockWhitelist or {}) do
        if type(ignoreCount) == "number" and ignoreCount > 0 then
            maxIgnoreCount = maxIgnoreCount + ignoreCount
        end
    end

    if count > maxIgnoreCount then
        return 0
    end
    return count
end

--- 判断射线到指定距离内是否被方块阻挡（消耗白名单次数）
--- @param origin table @射线起点坐标 {x, y, z}
--- @param dir table @单位方向向量 {x, y, z}
--- @param maxT number @最大检测距离
--- @return boolean @是否被阻挡
function Script:isBlockedByBlocks(origin, dir, maxT)
    local x, y, z = origin.x, origin.y, origin.z
    local ix, iy, iz = math.floor(x), math.floor(y), math.floor(z)
    local stepX = dir.x > 0 and 1 or -1
    local stepY = dir.y > 0 and 1 or -1
    local stepZ = dir.z > 0 and 1 or -1

    local tDeltaX = dir.x ~= 0 and math.abs(1 / dir.x) or math.huge
    local tDeltaY = dir.y ~= 0 and math.abs(1 / dir.y) or math.huge
    local tDeltaZ = dir.z ~= 0 and math.abs(1 / dir.z) or math.huge

    local nextBoundaryX = ix + (stepX > 0 and 1 or 0)
    local nextBoundaryY = iy + (stepY > 0 and 1 or 0)
    local nextBoundaryZ = iz + (stepZ > 0 and 1 or 0)

    local tMaxX = dir.x ~= 0 and ((nextBoundaryX - x) / dir.x) or math.huge
    local tMaxY = dir.y ~= 0 and ((nextBoundaryY - y) / dir.y) or math.huge
    local tMaxZ = dir.z ~= 0 and ((nextBoundaryZ - z) / dir.z) or math.huge

    local whitelist = blockWhitelist or {}
    local whitelistCounts = {}
    for blockId, count in pairs(whitelist) do
        whitelistCounts[blockId] = count
    end

    local function isWhitelisted(blockId)
        if not self.whitelistEnabled then
            return false
        end
        local count = whitelistCounts[blockId]
        if type(count) == "number" and count > 0 then
            whitelistCounts[blockId] = count - 1
            return true
        end
        return false
    end

    local t = 0
    while t <= maxT do
        local blockId = Block:GetBlockID(ix + 0.5, iy + 0.5, iz + 0.5)
        if blockId and blockId ~= 0 and not isWhitelisted(blockId) then
            return true
        end

        if tMaxX < tMaxY then
            if tMaxX < tMaxZ then
                ix = ix + stepX
                t = tMaxX
                tMaxX = tMaxX + tDeltaX
            else
                iz = iz + stepZ
                t = tMaxZ
                tMaxZ = tMaxZ + tDeltaZ
            end
        else
            if tMaxY < tMaxZ then
                iy = iy + stepY
                t = tMaxY
                tMaxY = tMaxY + tDeltaY
            else
                iz = iz + stepZ
                t = tMaxZ
                tMaxZ = tMaxZ + tDeltaZ
            end
        end
    end

    return false
end

--- 玩家枪械动作处理
--- @param event table @事件参数
--- @return nil @无返回
function Script:onPlayerAttackHit(event)
    local now = os.timeMs()
    local playerUin = event.eventobjid

    local cmpStructData = PlrDataMgr:GetPlrCmpStructData(playerUin, "limbSysCmp", "DATA")
    if now - cmpStructData.lastFireTime < 100 then
        return
    end
    cmpStructData.lastFireTime = now

    local eyeX, eyeY, eyeZ = Actor:GetPosition(playerUin)
    if not eyeX then
        return
    end
    eyeY = eyeY + self.EYE_HEIGHT

    local dir = Player:GetAimDir(playerUin)
    local len = math.sqrt(dir.x * dir.x + dir.y * dir.y + dir.z * dir.z)
    if len <= 0.0001 then
        return
    end
    dir.x, dir.y, dir.z = dir.x / len, dir.y / len, dir.z / len

    local origin = { x = eyeX, y = eyeY, z = eyeZ }
    local maxDist = self.MAX_DIST

    local targets = self:getAllTargets(eyeX, eyeY, eyeZ, maxDist, playerUin)
    local targetInfos = {}

    for _, target in ipairs(targets) do
        local objId = target.id
        local footX, footY, footZ = Actor:GetPosition(objId)
        if footX then
            local heightM = 2.0
            local halfWidth = 0.6
            local halfDepth = 0.6

            local minX, maxX = footX - halfWidth, footX + halfWidth
            local minY, maxY = footY, footY + heightM
            local minZ, maxZ = footZ - halfDepth, footZ + halfDepth

            local t = self:rayIntersectAABB(origin, dir, minX, minY, minZ, maxX, maxY, maxZ)
            if t and t > 0 and t <= maxDist then
                table.insert(targetInfos, {
                    id = objId,
                    t = t,
                    minX = minX,
                    maxX = maxX,
                    minY = minY,
                    maxY = maxY,
                    minZ = minZ,
                    maxZ = maxZ,
                    heightM = heightM,
                    halfWidth = halfWidth,
                })
            end
        end
    end

    if #targetInfos == 0 then
        return
    end
    table.sort(targetInfos, function(a, b)
        return a.t < b.t
    end)

    local bestHit = nil
    for _, info in ipairs(targetInfos) do
        local safeT = math.max(info.t - 0.2, 0)
        if not self:isBlockedByBlocks(origin, dir, safeT) or self.BLOCK_PENETRATION then
            local hitX = origin.x + dir.x * info.t
            local hitY = origin.y + dir.y * info.t
            local hitZ = origin.z + dir.z * info.t

            local eps = 0.01
            hitX = math.max(info.minX + eps, math.min(info.maxX - eps, hitX))
            hitY = math.max(info.minY + eps, math.min(info.maxY - eps, hitY))
            hitZ = math.max(info.minZ + eps, math.min(info.maxZ - eps, hitZ))

            bestHit = {
                id = info.id,
                x = hitX,
                y = hitY,
                z = hitZ,
                heightM = info.heightM,
                halfWidth = info.halfWidth,
            }
            break
        end
    end

    if bestHit then
        local part, ratio, lateralDist =
            self:getHitBodyPart(bestHit.id, bestHit.x, bestHit.y, bestHit.z, bestHit.heightM, bestHit.halfWidth)

        LogSys:Debug(
            string.format(
                "玩家 %d 攻击了 %d 的 %s | 纵向比例: %.2f | 横向距离: %.2f",
                playerUin,
                bestHit.id,
                part,
                ratio,
                lateralDist
            ),
            "Script:onPlayerAttackHit"
        )
    end
end

--- 获取命中部位
--- @param objId number @目标对象ID
--- @param hitX number @击中点X
--- @param hitY number @击中点Y
--- @param hitZ number @击中点Z
--- @param modelHeightM number @模型高度（米）
--- @param halfWidth number @半宽（米）
--- @return string, number, number @部位名称, 纵向比例, 横向距离
function Script:getHitBodyPart(objId, hitX, hitY, hitZ, modelHeightM, halfWidth)
    local footX, footY, footZ = Actor:GetPosition(objId)
    local ratio = (hitY - footY) / modelHeightM
    local dx = hitX - footX
    local dz = hitZ - footZ

    local yaw = Actor:GetFaceYaw(objId)
    local rad = math.rad(yaw)
    local forwardX = math.sin(rad)
    local forwardZ = math.cos(rad)
    local rightX = -forwardZ
    local rightZ = forwardX
    local lateralDist = math.abs(dx * rightX + dz * rightZ)
    local dot = dx * rightX + dz * rightZ

    -- 优先级: 头部 > 手臂 > 躯干 > 腹部 > 腿部

    -- 1. 头部
    if ratio >= self.HEAD_RATIO then
        return "头部", ratio, lateralDist
    end

    -- 2. 手臂（左/右）
    local isArm = false
    -- 极外侧（手臂明显伸出）
    if lateralDist > halfWidth * self.LATERAL_COEFF_EXTREME then
        isArm = true
    -- 手臂高度区域，横向距离超过阈值
    elseif ratio >= self.ARM_START_RATIO and lateralDist >= halfWidth * self.LATERAL_COEFF_HIGH then
        isArm = true
    -- 低高度区域（下垂手臂），且不低于腿部范围
    elseif lateralDist > halfWidth * self.LATERAL_COEFF_LOW and ratio >= self.LEG_RATIO then
        isArm = true
    end

    if isArm then
        local armSide = dot > 0 and "右臂" or "左臂"
        return armSide, ratio, lateralDist
    end

    -- 3. 躯干（不包含腹部区间）
    if ratio >= self.LEG_RATIO and ratio < self.HEAD_RATIO then
        if ratio >= self.ABDOMEN_MIN_RATIO and ratio <= self.ABDOMEN_MAX_RATIO then
            -- 是腹部区域，跳过，交给腹部判定
        else
            return "躯干", ratio, lateralDist
        end
    end

    -- 4. 腹部
    if ratio >= self.ABDOMEN_MIN_RATIO and ratio <= self.ABDOMEN_MAX_RATIO then
        return "腹部", ratio, lateralDist
    end

    -- 5. 腿部
    if ratio < self.LEG_RATIO then
        return "腿部", ratio, lateralDist
    end
    return "躯干", ratio, lateralDist
end

function Script:onGameAnyPlayerEnterGame(event)
    local playerUin = event.eventobjid
    if not self.whitelistEnabled then
        return
    end
    -- 每 0.01 秒检测玩家准星前的白名单方块数量
    local timerTask = self:DoPeriodicTask(function()
        local cmpStructData = PlrDataMgr:GetPlrCmpStructData(playerUin, "limbSysCmp", "DATA")
        local count = self:countWhitelistBlocksInSight(playerUin, self.MAX_DIST)
        if count == cmpStructData.lastBlockNum then
            goto skip
        else
            cmpStructData.lastBlockNum = count
        end
        for _, v in ipairs(Backpack:GetGunInstIdInBackpack(playerUin)) do
            local ret = Item:ModifyGunAttribute(v, GunAttr.Penetration, cmpStructData.lastBlockNum)
        end
        ::skip::
    end, 0.01)
end

return Script
