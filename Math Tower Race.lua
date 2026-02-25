--[[ 
    MATH SOLVER v4 – ULTIMATE ALL-IN-ONE (SMART CLICKING FOR ALL)
    Detects at (0.5, 0): math, rounding, sequences, percentages, comparisons,
    fractions, word problems, exponents
    After answer → 9s cooldown → auto‑restart (NOT scanning during cooldown)
    
    FEATURES:
    - safeEval() for chained/complex expressions via load()
    - Fraction arithmetic (1/2 + 1/3, etc.)
    - Advanced sequences (Fibonacci, quadratic second-differences, geometric)
    - runCooldown() helper — no more copy-pasted cooldown blocks
    - Word problem solver (plus/minus/times/divided by)
    - Exponent support (2^8, 3^3, etc.)
    - Wrong answer detection + accuracy tracking
    - SMART CLICKING: Finds and clicks the exact answer button for ALL question types
]]

--// SERVICES
local Players           = game:GetService("Players")
local VirtualInput      = game:GetService("VirtualInputManager")
local UserInputService  = game:GetService("UserInputService")

local player    = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")
local camera    = workspace.CurrentCamera

--// CONFIG
local CFG = {
    active       = false,
    scanInterval = 0.25,
    typeDelay    = 0.03,
    submitDelay  = 0.15,
}

--// STATS
local stats = {
    solved      = 0,
    attempts    = 0,
    timers      = 0,
    patterns    = 0,
    percentages = 0,
    comparisons = 0,
    fractions   = 0,
    words       = 0,
    wrong       = 0,
    accuracy    = 100,
}

local RESET_AFTER = 9  -- cooldown seconds

--// STATE
local lastAnsweredQuestion = ""
local lastAnswerTime       = 0
local inCooldown = false

--// ANSWER POSITIONS
local ANSWER_POSITIONS = {
    { 0.5,  0   }, -- question position
    { 1.0, -10  }, -- answer button (fallback position)
}

---------------------------------------------------------------------
--  OBSIDIAN UI SETUP
---------------------------------------------------------------------

local repo = "https://raw.githubusercontent.com/deividcomsono/Obsidian/main/"
local Library = loadstring(game:HttpGet(repo .. "Library.lua"))()
local ThemeManager = loadstring(game:HttpGet(repo .. "addons/ThemeManager.lua"))()
local SaveManager  = loadstring(game:HttpGet(repo .. "addons/SaveManager.lua"))()

local Options = Library.Options
local Toggles = Library.Toggles

local Window = Library:CreateWindow({
    Title        = "Math Solver",
    Footer       = "Smart Clicking v4",
    Center       = true,
    AutoShow     = true,
    Resizable    = true,
    NotifySide   = "Right",
    ShowCustomCursor = true,
})

local Tabs = {
    Main        = Window:AddTab("Solver", "calculator"),
    ["UI Settings"] = Window:AddTab("UI Settings", "settings"),
}

local StatusGroup  = Tabs.Main:AddLeftGroupbox("Status")
local StatsGroup   = Tabs.Main:AddRightGroupbox("Stats & Control")
local DebugDragger = Library:AddDraggableLabel("MathSolver: idle")

local statusLabel   = StatusGroup:AddLabel("STATUS: <font color='#FF5555'>Stopped</font>", false)
local questionLabel = StatusGroup:AddLabel("QUESTION: —", false)
local answerLabel   = StatusGroup:AddLabel("ANSWER: —", false)
StatusGroup:AddDivider()
local posLabel      = StatusGroup:AddLabel(" Smart Clicking Active for ALL", false)

local solvedLabel   = StatsGroup:AddLabel(" Solved: 0",      false)
local attemptsLabel = StatsGroup:AddLabel(" Attempts: 0",    false)
local wrongLabel    = StatsGroup:AddLabel(" Wrong: 0",        false)
local accuracyLabel = StatsGroup:AddLabel(" Accuracy: 100%", false)
StatsGroup:AddDivider()
local timerLabel    = StatsGroup:AddLabel(" Timers: 0",      false)
local patternLabel  = StatsGroup:AddLabel(" Patterns: 0",    false)
local percentLabel  = StatsGroup:AddLabel(" Percent: 0",      false)
local compareLabel  = StatsGroup:AddLabel(" Comparisons: 0",  false)
local fractionLabel = StatsGroup:AddLabel(" Fractions: 0",    false)
local wordLabel     = StatsGroup:AddLabel(" Word Problems: 0",false)

--// THEME & CONFIG
ThemeManager:SetLibrary(Library)
SaveManager:SetLibrary(Library)
ThemeManager:SetFolder("ZyCrypticz/MathSolver")
SaveManager:SetFolder("ZyCrypticz/MathSolver")
ThemeManager:ApplyToTab(Tabs["UI Settings"])
SaveManager:IgnoreThemeSettings()
SaveManager:SetIgnoreIndexes({ "MenuKeybind" })
SaveManager:BuildConfigSection(Tabs["UI Settings"])
SaveManager:LoadAutoloadConfig()

---------------------------------------------------------------------
--  HELPER: RICH TEXT
---------------------------------------------------------------------

local function rich(color, text)
    return string.format("<font color='%s'>%s</font>", color, text)
end

---------------------------------------------------------------------
--  COOLDOWN HELPER
---------------------------------------------------------------------

local function runCooldown()
    print("⏸️ COOLDOWN STARTED -", RESET_AFTER, "seconds")
    inCooldown = true
    for i = RESET_AFTER, 1, -1 do
        statusLabel:SetText("STATUS: " .. rich("#FFA028", "Restarting in " .. i .. "s..."))
        task.wait(1)
    end
    questionLabel:SetText("QUESTION: —")
    answerLabel:SetText("ANSWER: —")
    inCooldown = false
    statusLabel:SetText("STATUS: " .. rich("#00D278", "Running"))
    print("▶️ COOLDOWN ENDED")
end

---------------------------------------------------------------------
--  CLASSIFICATION
---------------------------------------------------------------------

local function classify(text)
    if not text or text == "" then return "none" end
    if text:match("^%d+[:%.]%d+$") then return "timer" end
    if text:match("%[%?%]") then return "comparison" end
    if text:match("%d+%.?%d*%%") or text:match("What is the fraction") then return "percentage" end
    if text:match("Round to the nearest whole number") then return "rounding" end
    if text:match("%d+,%s*%d+,%s*%d+,%s*%?") then return "sequence" end
    -- Fraction arithmetic: e.g. 1/2 + 1/3
    if text:match("%d+%s*/%s*%d+%s*[%+%-%*]%s*%d+%s*/%s*%d+") then return "fraction" end
    -- Exponents: 2^8
    if text:match("%d+%^%d+") then return "exponent" end
    -- Word problems
    if text:match("plus") or text:match("minus") or text:match("times") or text:match("divided by") then return "word" end
    -- MATH - improved to catch ÷ symbol
    if text:match("%d+%s*[%+%-%*xX/]%s*%d+") or text:match("%d+%s*×%s*%d+") or text:match("%d+%s*÷%s*%d+") then 
        return "math" 
    end
    return "other"
end

---------------------------------------------------------------------
--  SOLVING FUNCTIONS
---------------------------------------------------------------------

-- GCD helper
local function gcd(a, b)
    a, b = math.abs(a), math.abs(b)
    while b ~= 0 do a, b = b, a % b end
    return a
end

-- Safe expression evaluator using load()
local function safeEval(expr)
    expr = expr
        :gsub("×", "*")    -- Replaced as an exact string
        :gsub("[xX]", "*") -- Normal letters are safe in brackets
        :gsub("÷", "/")
        :gsub("%^", "^")
        :gsub("%s+", "")
        :gsub("[%?=]", "")
    local fn, err = load("return " .. expr)
    if fn then
        local ok, result = pcall(fn)
        if ok and type(result) == "number" and result == result then
            if math.abs(result - math.floor(result)) < 0.001 then
                return tostring(math.floor(result))
            end
            return string.format("%.2f", result)
        end
    end
    return nil
end

-- Comparison solver
local function evaluateTerm(term)
    term = term:gsub("%s", "")
    local num, den = term:match("(%d+)/(%d+)")
    if num and den then return tonumber(num) / tonumber(den) end
    local p = term:match("(%d+%.?%d*)%%")
    if p then return tonumber(p) / 100 end
    return tonumber(term)
end

local function solveComparison(text)
    local left, right = text:match("(.-)%s*%[%?%]%s*(.+)")
    if not left or not right then return nil end
    left  = left:gsub("%s+", "")
    right = right:gsub("%s+", "")
    local lv = evaluateTerm(left)
    local rv = evaluateTerm(right)
    if not lv or not rv then return nil end
    if math.abs(lv - rv) < 0.0001 then return "="
    elseif lv > rv then return ">"
    else return "<" end
end

-- Percentage → fraction solver
local function solvePercentage(text)
    local percent = text:match("([%d%.]+)%%")
    if not percent then return nil end
    local num = tonumber(percent)
    if not num then return nil end
    local common = {
        [12.5]="1/8",  [20]="1/5",   [25]="1/4",  [33.33]="1/3",
        [37.5]="3/8",  [40]="2/5",   [50]="1/2",  [60]="3/5",
        [62.5]="5/8",  [66.67]="2/3",[75]="3/4",  [80]="4/5",
        [83.33]="5/6", [87.5]="7/8"
    }
    for p, f in pairs(common) do
        if math.abs(num - p) < 0.01 then return f end
    end
    local denominator = 100
    local numerator   = math.floor(num * denominator / 100 + 0.5)
    local d = gcd(numerator, denominator)
    if d > 1 then
        return tostring(numerator / d) .. "/" .. tostring(denominator / d)
    end
    return tostring(numerator) .. "/" .. tostring(denominator)
end

-- Advanced sequence solver
local function solveSequence(text)
    local nums = {}
    for n in text:gmatch("%-?%d+%.?%d*") do
        table.insert(nums, tonumber(n))
    end
    if #nums < 3 then return nil end

    -- Fibonacci check
    local isFib = true
    for i = 3, #nums do
        if nums[i] ~= nums[i-1] + nums[i-2] then isFib = false; break end
    end
    if isFib then
        return tostring(nums[#nums - 1] + nums[#nums])
    end

    -- Arithmetic
    local d1 = {}
    for i = 2, #nums do d1[i-1] = nums[i] - nums[i-1] end
    local arith = true
    for i = 2, #d1 do if d1[i] ~= d1[1] then arith = false; break end end
    if arith then return tostring(nums[#nums] + d1[1]) end

    -- Quadratic
    local d2 = {}
    for i = 2, #d1 do d2[i-1] = d1[i] - d1[i-1] end
    local quad = true
    for i = 2, #d2 do if d2[i] ~= d2[1] then quad = false; break end end
    if quad and #d2 >= 1 then
        return tostring(nums[#nums] + d1[#d1] + d2[1])
    end

    -- Geometric
    if nums[1] ~= 0 then
        local r = nums[2] / nums[1]
        local isGeo = true
        for i = 2, #nums - 1 do
            if math.abs(nums[i+1] / nums[i] - r) > 0.001 then isGeo = false; break end
        end
        if isGeo then
            local nxt = nums[#nums] * r
            if math.abs(nxt - math.floor(nxt)) < 0.001 then
                return tostring(math.floor(nxt))
            end
            return string.format("%.2f", nxt)
        end
    end

    return nil
end

-- Rounding solver
local function solveRounding(text)
    local num = text:match("(%d+%.%d+)") or text:match("(%d+)")
    if num then
        local n = tonumber(num)
        if n then return tostring(math.floor(n + 0.5)) end
    end
    return nil
end

-- Fraction arithmetic solver
local function solveFraction(text)
    local n1, d1, op, n2, d2 = text:match("(%d+)%s*/%s*(%d+)%s*([%+%-%*])%s*(%d+)%s*/%s*(%d+)")
    if not n1 then return nil end
    n1, d1, n2, d2 = tonumber(n1), tonumber(d1), tonumber(n2), tonumber(d2)
    local rn, rd
    if op == "+" then
        rn, rd = n1 * d2 + n2 * d1, d1 * d2
    elseif op == "-" then
        rn, rd = n1 * d2 - n2 * d1, d1 * d2
    elseif op == "*" then
        rn, rd = n1 * n2, d1 * d2
    else
        return nil
    end
    local g = gcd(math.abs(rn), rd)
    rn, rd = rn / g, rd / g
    if rd == 1 then return tostring(rn) end
    return rn .. "/" .. rd
end

-- Exponent solver
local function solveExponent(text)
    local base, exp = text:match("(%d+)%^(%d+)")
    if base and exp then
        local result = tonumber(base) ^ tonumber(exp)
        if math.abs(result - math.floor(result)) < 0.001 then
            return tostring(math.floor(result))
        end
        return string.format("%.2f", result)
    end
    return nil
end

-- Word problem solver
local function solveWordProblem(text)
    local low = text:lower()
    -- Pattern: "X plus/minus/times/divided by Y"
    local a, op, b = low:match("(%d+)%s+(plus|minus|times|divided by)%s+(%d+)")
    if a and op and b then
        a, b = tonumber(a), tonumber(b)
        if op == "plus"       then return tostring(a + b) end
        if op == "minus"      then return tostring(a - b) end
        if op == "times"      then return tostring(a * b) end
        if op == "divided by" and b ~= 0 then
            local r = a / b
            if math.abs(r - math.floor(r)) < 0.001 then return tostring(math.floor(r)) end
            return string.format("%.2f", r)
        end
    end
    -- Pattern: "What is X + Y?" or similar
    local expr = text:match("([%d%s%+%-%*/%^×÷xX]+)%s*%?")
    if expr then return safeEval(expr) end
    return nil
end

-- Main math solver
local function solveMath(expr)
    if not expr then return nil end
    
    -- Debug the raw input
    print("🔍 solveMath RAW:", expr)
    
    -- Try to extract just the math part (remove anything after = if present)
    local mathPart = expr:match("(.-)%s*=%s*%?+") or expr
    
    local e = mathPart
        :gsub("×", "*")    -- Replaced as an exact string
        :gsub("[xX]", "*") -- Normal letters are safe in brackets
        :gsub("÷", "/")
        :gsub("%s+", " ")
        :match("^%s*(.-)%s*$")
    
    -- Debug the cleaned expression
    print("🔍 solveMath CLEANED:", e)

    -- DIVISION
    local a, b = e:match("(%d+)%s*/%s*(%d+)")
    if a and b then
        print("✅ Division matched:", a, "/", b)
        a, b = tonumber(a), tonumber(b)
        if a and b and b ~= 0 then
            local r = a / b
            print("✅ Result:", r)
            if math.abs(r - math.floor(r)) < 0.001 then 
                return tostring(math.floor(r))
            else 
                return string.format("%.2f", r) 
            end
        end
    end

    -- Multiplication
    a, b = e:match("(%d+)%s*%*%s*(%d+)")
    if a and b then
        a, b = tonumber(a), tonumber(b)
        if a and b then 
            print("✅ Multiplication:", a * b)
            return tostring(a * b) 
        end
    end

    -- Subtraction
    a, b = e:match("(%d+)%s*%-%s*(%d+)")
    if a and b then
        a, b = tonumber(a), tonumber(b)
        if a and b then 
            print("✅ Subtraction:", a - b)
            return tostring(a - b) 
        end
    end

    -- Addition
    a, b = e:match("(%d+)%s*%+%s*(%d+)")
    if a and b then
        a, b = tonumber(a), tonumber(b)
        if a and b then 
            print("✅ Addition:", a + b)
            return tostring(a + b) 
        end
    end

    -- safeEval fallback
    print("⚠️ No pattern matched, trying safeEval")
    return safeEval(e)
end

---------------------------------------------------------------------
--  SMART CLICKING FUNCTION - Finds and clicks the exact answer button
---------------------------------------------------------------------

local function clickAnswerButtonWithValue(targetValue)
    print("🔍 Looking for button with value:", targetValue)
    
    -- Convert targetValue to string for comparison
    local targetStr = tostring(targetValue)
    
    -- Search through all GUI elements in playerGui
    local function searchInInstance(instance)
        for _, obj in ipairs(instance:GetDescendants()) do
            -- Check TextButtons directly
            if obj:IsA("TextButton") then
                -- Safely check Text property
                local success, textValue = pcall(function()
                    return obj.Text
                end)
                
                if success and textValue and textValue == targetStr then
                    print("✅ Found TextButton with text:", textValue)
                    local pos = obj.AbsolutePosition
                    local size = obj.AbsoluteSize
                    return pos.X + size.X/2, pos.Y + size.Y/2
                end
            end
            
            -- Check ImageButtons (they might have TextLabel children)
            if obj:IsA("ImageButton") then
                -- Check if the ImageButton itself has text (rare)
                local success, textValue = pcall(function()
                    return obj.Text
                end)
                
                if success and textValue and textValue == targetStr then
                    print("✅ Found ImageButton with text:", textValue)
                    local pos = obj.AbsolutePosition
                    local size = obj.AbsoluteSize
                    return pos.X + size.X/2, pos.Y + size.Y/2
                end
                
                -- Check children TextLabels
                for _, child in ipairs(obj:GetChildren()) do
                    if child:IsA("TextLabel") and child.Text == targetStr then
                        print("✅ Found ImageButton with child TextLabel:", child.Text)
                        -- Click the parent button, not the text label
                        local pos = obj.AbsolutePosition
                        local size = obj.AbsoluteSize
                        return pos.X + size.X/2, pos.Y + size.Y/2
                    end
                end
            end
            
            -- Check TextLabels that might be clickable (in a frame that acts as button)
            if obj:IsA("TextLabel") and obj.Text == targetStr then
                -- Check if parent is clickable
                local parent = obj.Parent
                if parent:IsA("TextButton") or parent:IsA("ImageButton") then
                    print("✅ Found TextLabel with clickable parent")
                    local pos = parent.AbsolutePosition
                    local size = parent.AbsoluteSize
                    return pos.X + size.X/2, pos.Y + size.Y/2
                end
            end
        end
        return nil
    end
    
    -- Search in playerGui
    local x, y = searchInInstance(playerGui)
    
    -- If found, click at that position
    if x and y then
        print("🖱️ Clicking at:", x, y)
        VirtualInput:SendMouseButtonEvent(x, y, 0, true, game, 0)
        task.wait(0.05)
        VirtualInput:SendMouseButtonEvent(x, y, 0, false, game, 0)
        task.wait(0.05)
        return true
    end
    
    -- If not found, try the default position as fallback
    print("⚠️ Button not found, using default position")
    local sx, sy = ANSWER_POSITIONS[2][1], ANSWER_POSITIONS[2][2]
    local ax = sx * camera.ViewportSize.X
    local ay = sy < 0 and camera.ViewportSize.Y + sy or sy * camera.ViewportSize.Y
    VirtualInput:SendMouseButtonEvent(ax, ay, 0, true, game, 0)
    task.wait(0.05)
    VirtualInput:SendMouseButtonEvent(ax, ay, 0, false, game, 0)
    task.wait(0.05)
    
    return false
end

---------------------------------------------------------------------
--  INPUT HELPERS
---------------------------------------------------------------------

local function getTextAt(sx, sy)
    local ax = sx * camera.ViewportSize.X
    local ay = sy < 0 and camera.ViewportSize.Y + sy or sy * camera.ViewportSize.Y
    for _, el in ipairs(playerGui:GetGuiObjectsAtPosition(ax, ay)) do
        if (el:IsA("TextLabel") or el:IsA("TextBox")) and #el.Text > 0 then
            local short = #el.Text > 64 and el.Text:sub(1, 61) .. "..." or el.Text
            DebugDragger:SetText("Q: " .. short)
            return el.Text, el
        end
    end
    DebugDragger:SetText("MathSolver: scanning...")
    return nil, nil
end

local function pressKey(kc, shift)
    if shift then
        VirtualInput:SendKeyEvent(true, Enum.KeyCode.LeftShift, false, game)
        task.wait(0.02)
    end
    VirtualInput:SendKeyEvent(true,  kc, false, game)
    task.wait(0.02)
    VirtualInput:SendKeyEvent(false, kc, false, game)
    task.wait(0.02)
    if shift then
        VirtualInput:SendKeyEvent(false, Enum.KeyCode.LeftShift, false, game)
        task.wait(0.02)
    end
end

-- Type string function (only used for comparison symbols now)
local function typeString(str)
    for i = 1, #str do
        local c = str:sub(i, i)
        
        -- Handle special characters
        if c == "<" then 
            pressKey(Enum.KeyCode.Comma, true)
        elseif c == ">" then 
            pressKey(Enum.KeyCode.Period, true)
        elseif c == "=" then 
            pressKey(Enum.KeyCode.Equals, false)
        elseif c == "." then 
            pressKey(Enum.KeyCode.Period, false)
        elseif c == "-" then 
            pressKey(Enum.KeyCode.Minus, false)
        elseif c == "/" then 
            pressKey(Enum.KeyCode.Slash, false)
        -- Handle numbers (though we now use clicking for these)
        elseif c == "0" then pressKey(Enum.KeyCode.Zero, false)
        elseif c == "1" then pressKey(Enum.KeyCode.One, false)
        elseif c == "2" then pressKey(Enum.KeyCode.Two, false)
        elseif c == "3" then pressKey(Enum.KeyCode.Three, false)
        elseif c == "4" then pressKey(Enum.KeyCode.Four, false)
        elseif c == "5" then pressKey(Enum.KeyCode.Five, false)
        elseif c == "6" then pressKey(Enum.KeyCode.Six, false)
        elseif c == "7" then pressKey(Enum.KeyCode.Seven, false)
        elseif c == "8" then pressKey(Enum.KeyCode.Eight, false)
        elseif c == "9" then pressKey(Enum.KeyCode.Nine, false)
        -- Handle letters
        else
            local kc = Enum.KeyCode[c:upper()]
            if kc then 
                pressKey(kc, true)
            end
        end
        task.wait(CFG.typeDelay)
    end
end

---------------------------------------------------------------------
--  UI UPDATE
---------------------------------------------------------------------

local mainLoopRunning = false
local SolverToggle

local function updateUI()
    local on = CFG.active
    statusLabel:SetText("STATUS: " .. (on and rich("#00D278", "Running") or rich("#FF5555", "Stopped")))
    solvedLabel:SetText(" Solved: "          .. stats.solved)
    attemptsLabel:SetText(" Attempts: "      .. stats.attempts)
    wrongLabel:SetText(" Wrong: "             .. stats.wrong)
    accuracyLabel:SetText(" Accuracy: "      .. stats.accuracy .. "%")
    timerLabel:SetText(" Timers: "           .. stats.timers)
    patternLabel:SetText(" Patterns: "       .. stats.patterns)
    percentLabel:SetText(" Percent: "         .. stats.percentages)
    compareLabel:SetText(" Comparisons: "     .. stats.comparisons)
    fractionLabel:SetText(" Fractions: "      .. stats.fractions)
    wordLabel:SetText(" Word Problems: "     .. stats.words)
end

local function updateAccuracy()
    local total = stats.solved + stats.wrong
    stats.accuracy = total > 0 and math.floor((stats.solved / total) * 100) or 100
end

---------------------------------------------------------------------
--  ANSWER + COOLDOWN HANDLER - SMART CLICKING FOR ALL TYPES
---------------------------------------------------------------------

local function handleAnswer(kind, label, ans, text)
    if not ans then return false end

    answerLabel:SetText("ANSWER: " .. rich("#00D278", ans))
    print(string.format("✅ [%s] %s → %s", kind, text, ans))

    -- For ALL question types except comparison symbols, use smart clicking
    if kind == "comparison" then
        -- Comparison symbols (<, >, =) need to be typed
        typeString(ans)
        pressKey(Enum.KeyCode.Return, false)
    else
        -- For EVERYTHING else (math, rounding, sequence, percentage, fraction, exponent, word), click the button
        clickAnswerButtonWithValue(ans)
    end

    lastAnsweredQuestion = text
    lastAnswerTime       = tick()
    stats.solved        += 1
    updateAccuracy()
    updateUI()
    runCooldown()
    return true
end

---------------------------------------------------------------------
--  WRONG ANSWER DETECTION
---------------------------------------------------------------------

local function checkWrongAnswer(text)
    -- If the same question reappears within 5 seconds of answering, we likely got it wrong
    if text == lastAnsweredQuestion and tick() - lastAnswerTime < 5 then
        stats.wrong   += 1
        updateAccuracy()
        Library:Notify("⚠️ Wrong answer detected! Accuracy: " .. stats.accuracy .. "%", 3)
        lastAnsweredQuestion = "" -- Reset so we try again
        return true
    end
    return false
end

---------------------------------------------------------------------
--  MAIN LOOP - All types use handleAnswer
---------------------------------------------------------------------

local function mainLoop()
    if mainLoopRunning then return end
    mainLoopRunning = true
    print(" Math Solver v4 loop started")

    while CFG.active do
        if inCooldown then 
            task.wait(1)
            continue 
        end

        local text, _ = getTextAt(ANSWER_POSITIONS[1][1], ANSWER_POSITIONS[1][2])
        if text then
            local kind = classify(text)

            if kind ~= "timer" then
                print(" Detected:", text, "->", kind)
            end

            if kind == "timer" then
                stats.timers += 1
                updateUI()

            elseif kind == "comparison" then
                if checkWrongAnswer(text) then
                    -- will retry
                elseif not (text == lastAnsweredQuestion and tick() - lastAnswerTime < 30) then
                    stats.attempts  += 1
                    stats.comparisons += 1
                    questionLabel:SetText("COMPARE: " .. text)
                    answerLabel:SetText("ANSWER: …")
                    updateUI()
                    handleAnswer("comparison", questionLabel, solveComparison(text), text)
                end

            elseif kind == "percentage" then
                if checkWrongAnswer(text) then
                elseif not (text == lastAnsweredQuestion and tick() - lastAnswerTime < 30) then
                    stats.attempts    += 1
                    stats.percentages += 1
                    questionLabel:SetText("PERCENT: " .. text)
                    answerLabel:SetText("ANSWER: …")
                    updateUI()
                    handleAnswer("percentage", questionLabel, solvePercentage(text), text)
                end

            elseif kind == "sequence" then
                if checkWrongAnswer(text) then
                elseif not (text == lastAnsweredQuestion and tick() - lastAnswerTime < 30) then
                    stats.attempts += 1
                    stats.patterns += 1
                    questionLabel:SetText("SEQUENCE: " .. text)
                    answerLabel:SetText("ANSWER: …")
                    updateUI()
                    handleAnswer("sequence", questionLabel, solveSequence(text), text)
                end

            elseif kind == "rounding" then
                if checkWrongAnswer(text) then
                elseif not (text == lastAnsweredQuestion and tick() - lastAnswerTime < 30) then
                    stats.attempts += 1
                    local num = text:match("(%d+%.%d+)") or text:match("(%d+)")
                    questionLabel:SetText("ROUNDING: " .. (num and ("Round " .. num) or "?"))
                    answerLabel:SetText("ANSWER: …")
                    updateUI()
                    handleAnswer("rounding", questionLabel, solveRounding(text), text)
                end

            elseif kind == "fraction" then
                if checkWrongAnswer(text) then
                elseif not (text == lastAnsweredQuestion and tick() - lastAnswerTime < 30) then
                    stats.attempts  += 1
                    stats.fractions += 1
                    questionLabel:SetText("FRACTION: " .. text)
                    answerLabel:SetText("ANSWER: …")
                    updateUI()
                    handleAnswer("fraction", questionLabel, solveFraction(text), text)
                end

            elseif kind == "exponent" then
                if checkWrongAnswer(text) then
                elseif not (text == lastAnsweredQuestion and tick() - lastAnswerTime < 30) then
                    stats.attempts += 1
                    questionLabel:SetText("EXPONENT: " .. text)
                    answerLabel:SetText("ANSWER: …")
                    updateUI()
                    handleAnswer("exponent", questionLabel, solveExponent(text), text)
                end

            elseif kind == "word" then
                if checkWrongAnswer(text) then
                elseif not (text == lastAnsweredQuestion and tick() - lastAnswerTime < 30) then
                    stats.attempts += 1
                    stats.words    += 1
                    questionLabel:SetText("WORD: " .. text)
                    answerLabel:SetText("ANSWER: …")
                    updateUI()
                    handleAnswer("word", questionLabel, solveWordProblem(text), text)
                end

            elseif kind == "math" then
                if checkWrongAnswer(text) then
                elseif not (text == lastAnsweredQuestion and tick() - lastAnswerTime < 30) then
                    stats.attempts += 1
                    local clean = text
                        :gsub("=", "")
                        :gsub("%?", "")
                        :gsub("%s+", " ")
                        :match("^%s*(.-)%s*$")
                    questionLabel:SetText("MATH: " .. clean)
                    answerLabel:SetText("ANSWER: …")
                    updateUI()
                    
                    -- Solve math
                    local ans = solveMath(clean)
                    if ans then
                        answerLabel:SetText("ANSWER: " .. rich("#00D278", ans))
                        print("✅ [math]", clean, "→", ans)
                        
                        -- Use smart clicking for math answers
                        handleAnswer("math", questionLabel, ans, text)
                    else
                        print("❌ No answer found for:", clean)
                    end
                end
            end
        end

        task.wait(CFG.scanInterval)
    end

    mainLoopRunning = false
    inCooldown      = false
    print("🛑 Main loop ended")
end

---------------------------------------------------------------------
--  CONTROLS
---------------------------------------------------------------------

SolverToggle = StatsGroup:AddToggle("SolverActive", {
    Text    = "Enable solver (F6)",
    Default = false,
})
Toggles.SolverActive:OnChanged(function(state)
    CFG.active = state
    if state then
        questionLabel:SetText("QUESTION: —")
        answerLabel:SetText("ANSWER: —")
        inCooldown = false
        updateUI()
        task.spawn(mainLoop)
        Library:Notify("Solver v4 started – SMART CLICKING for ALL types!", 2)
    else
        updateUI()
        Library:Notify("Solver stopped", 2)
    end
end)

StatsGroup:AddButton({
    Text = "Start / Stop (F6)",
    Func = function() SolverToggle:SetValue(not Toggles.SolverActive.Value) end
})

StatsGroup:AddButton({
    Text = "Test Solve (Debug)",
    Func = function()
        local text, _ = getTextAt(ANSWER_POSITIONS[1][1], ANSWER_POSITIONS[1][2])
        if text then
            local kind = classify(text)
            local ans
            if     kind == "math"       then ans = solveMath(text)
            elseif kind == "rounding"   then ans = solveRounding(text)
            elseif kind == "sequence"   then ans = solveSequence(text)
            elseif kind == "percentage" then ans = solvePercentage(text)
            elseif kind == "comparison" then ans = solveComparison(text)
            elseif kind == "fraction"   then ans = solveFraction(text)
            elseif kind == "exponent"   then ans = solveExponent(text)
            elseif kind == "word"       then ans = solveWordProblem(text)
            end
            Library:Notify(string.format("Test: %s → %s", kind, ans or "none"), 3)
        else
            Library:Notify("No text detected", 2)
        end
    end
})

StatsGroup:AddButton({
    Text = "Reset Stats",
    Func = function()
        for k in pairs(stats) do stats[k] = 0 end
        stats.accuracy = 100
        updateUI()
        Library:Notify("Stats reset", 2)
    end
})

-- Menu keybind
local MenuGroup = Tabs["UI Settings"]:AddLeftGroupbox("Menu")
MenuGroup:AddLabel("Menu keybind"):AddKeyPicker("MenuKeybind", {
    Default = "RightShift",
    NoUI    = true,
    Text    = "Menu keybind"
})
Library.ToggleKeybind = Options.MenuKeybind

-- F6 toggles solver
UserInputService.InputBegan:Connect(function(input, gpe)
    if not gpe and input.KeyCode == Enum.KeyCode.F6 then
        SolverToggle:SetValue(not Toggles.SolverActive.Value)
    end
end)

Library:OnUnload(function()
    CFG.active = false
    inCooldown = false
end)

updateUI()
Library:Notify("MathSolver v4 loaded – SMART CLICKING for ALL question types!", 5)
