local Script = {}

local CONFIG = {
    EYE_HEIGHT = 1.6,
    MAX_DIST = 100,
    STEP_SIZE = 0.0075,
    LEG_RATIO = 0.3,
    HEAD_RATIO = 0.8,
    ARM_START_RATIO = 0.4, -- 手臂起始高度
    LATERAL_COEFF_HIGH = 0.4, -- 手臂区域横向偏移系数（×半宽）
    LATERAL_COEFF_LOW = 0.5, -- 低高度区域横向偏移系数
    LATERAL_COEFF_EXTREME = 0.7, -- 极外侧横向系数
}

--- 脚本入口
--- @return nil @无返回
function Script:OnStart()
    self.lastFireTime = 0
    self:AddTriggerEvent(TriggerEvent.PlayerAttackHit, self.onPlayerAttackHit)
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
                if dx*dx + dy*dy + dz*dz <= radius*radius then
                    table.insert(targets, {id = uin, type = "player"})
                end
            end
        end
    end
    local posBeg = {x = centerX - radius, y = centerY - radius, z = centerZ - radius}
    local posEnd = {x = centerX + radius, y = centerY + radius, z = centerZ + radius}
    local creatures = Area:GetAllCreaturesInAreaRange(posBeg, posEnd)
    if creatures then
        for _, mobId in ipairs(creatures) do
            if Actor:IsExist(mobId) then
                table.insert(targets, {id = mobId, type = "mob"})
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
    if tmax < 0 or tmin > tmax then return nil end
    return tmin
end

--- 玩家枪械动作处理
--- @param event table @事件参数
--- @return nil @无返回
function Script:onPlayerAttackHit(event)
    local now = os.timeMs()
    if now - self.lastFireTime < 100 then return end
    self.lastFireTime = now

    local playerUin = event.eventobjid
    if not playerUin or not Actor:IsExist(playerUin) then return end

    local eyeX, eyeY, eyeZ = Actor:GetPosition(playerUin)
    eyeY = eyeY + CONFIG.EYE_HEIGHT
    local dir = Player:GetAimDir(playerUin)
    if not dir then return end
    local len = math.sqrt(dir.x * dir.x + dir.y * dir.y + dir.z * dir.z)
    if len > 0 then
        dir.x = dir.x / len
        dir.y = dir.y / len
        dir.z = dir.z / len
    else
        return
    end

    local origin = {x = eyeX, y = eyeY, z = eyeZ}
    local maxDist = CONFIG.MAX_DIST
    local step = CONFIG.STEP_SIZE

    local targets = self:getAllTargets(eyeX, eyeY, eyeZ, maxDist, playerUin)
    local targetInfos = {}
    for _, target in ipairs(targets) do
        local objId = target.id
        local footX, footY, footZ = Actor:GetPosition(objId)
        if footX then
            local bound = Actor:GetBoundSzie(objId)
            if bound then
                local heightM = bound.y / 100
                local halfWidth = bound.x / 2 / 100
                local halfDepth = bound.z / 2 / 100
                local minX = footX - halfWidth
                local maxX = footX + halfWidth
                local minY = footY
                local maxY = footY + heightM
                local minZ = footZ - halfDepth
                local maxZ = footZ + halfDepth
                local t = self:rayIntersectAABB(origin, dir, minX, minY, minZ, maxX, maxY, maxZ)
                if t and t > 0 and t <= maxDist then
                    table.insert(targetInfos, {
                        id = objId,
                        t = t,
                        minX = minX, maxX = maxX,
                        minY = minY, maxY = maxY,
                        minZ = minZ, maxZ = maxZ,
                        heightM = heightM,
                        halfWidth = halfWidth
                    })
                end
            end
        end
    end

    table.sort(targetInfos, function(a, b) return a.t < b.t end)

    local bestHit = nil
    for _, info in ipairs(targetInfos) do
        local blocked = false
        local t_step = 0
        while t_step <= info.t do
            local x = origin.x + dir.x * t_step
            local y = origin.y + dir.y * t_step
            local z = origin.z + dir.z * t_step
            local blockId = Block:GetBlockID(x, y, z)
            if blockId and blockId ~= 0 then
                blocked = true
                break
            end
            t_step = t_step + step
        end
        if not blocked then
            local hitX = origin.x + dir.x * info.t
            local hitY = origin.y + dir.y * info.t
            local hitZ = origin.z + dir.z * info.t
            hitX = math.max(info.minX, math.min(info.maxX, hitX))
            hitY = math.max(info.minY, math.min(info.maxY, hitY))
            hitZ = math.max(info.minZ, math.min(info.maxZ, hitZ))
            bestHit = {id = info.id, x = hitX, y = hitY, z = hitZ, heightM = info.heightM, halfWidth = info.halfWidth}
            break
        end
    end

    if not bestHit then return end

    local part = self:getHitBodyPart(bestHit.id, bestHit.x, bestHit.y, bestHit.z, bestHit.heightM, bestHit.halfWidth)
    print(string.format("玩家 %d 开枪击中 %d 的 %s (击中点: %.4f, %.4f, %.4f)", 
        playerUin, bestHit.id, part, bestHit.x, bestHit.y, bestHit.z))
end

--- 获取攻击部位
--- @param objId number @目标对象ID
--- @param hitX number @击中点X坐标
--- @param hitY number @击中点Y坐标
--- @param hitZ number @击中点Z坐标
--- @param modelHeightM number @模型高度（米）
--- @param halfWidth number @模型半宽（米）
--- @return string @攻击部位名称
function Script:getHitBodyPart(objId, hitX, hitY, hitZ, modelHeightM, halfWidth)
    local footX, footY, footZ = Actor:GetPosition(objId)
    if not footX then return "未知" end

    local ratio = (hitY - footY) / modelHeightM
    local dx = hitX - footX
    local dz = hitZ - footZ

    -- 获取角色的左右方向向量
    local yaw = Actor:GetFaceYaw(objId)
    local rad = math.rad(yaw)
    local forwardX = math.sin(rad)
    local forwardZ = math.cos(rad)
    local rightX = -forwardZ
    local rightZ = forwardX
    local lateralDist = math.abs(dx * rightX + dz * rightZ)
    local dot = dx * rightX + dz * rightZ   -- 用于左右臂区分

    -- 优先判定头部和腿部（不受横向偏移干扰）
    if ratio >= CONFIG.HEAD_RATIO then
        return "头部"
    end
    if ratio < CONFIG.LEG_RATIO then
        return "腿部"
    end

    -- 极外侧判定（手臂明显伸出）
    if lateralDist > halfWidth * CONFIG.LATERAL_COEFF_EXTREME then
        return dot > 0 and "右臂" or "左臂"
    end

    -- 正常高度手臂区域
    if ratio >= CONFIG.ARM_START_RATIO then
        if lateralDist < halfWidth * CONFIG.LATERAL_COEFF_HIGH then
            return "躯干"
        end
        return dot > 0 and "右臂" or "左臂"
    end

    -- 低高度区域（下垂手臂）
    if lateralDist > halfWidth * CONFIG.LATERAL_COEFF_LOW then
        return dot > 0 and "右臂" or "左臂"
    else
        return "躯干"
    end
end

return Script