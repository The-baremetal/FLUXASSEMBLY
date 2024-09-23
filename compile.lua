local function readFile(filePath)
    local file = io.open(filePath, "r")
    if not file then
        error("Could not open file: " .. filePath)
    end
    local content = file:read("*all")
    file:close()
    return content
end

local function writeFile(filePath, content)
    local file = io.open(filePath, "w")
    if not file then
        error("Could not write to file: " .. filePath)
    end
    file:write(content)
    file:close()
end

local sections = {}

local function addSection(sectionName)
    if not sections[sectionName] then
        sections[sectionName] = {}
    end
end

local function addToSection(sectionName, code)
    addSection(sectionName)
    table.insert(sections[sectionName], code)
end

local function generateVgaBuffer()
    return "vgaBuffer: dw 0xB8000"
end

local function generateVariable(name, value)
    return string.format("%s: db '%s', 0", name, value)
end

local function generateFunctionCall(funcName, arg)
    return string.format([[ 
    ; Call %s 
    mov dx, %s 
    mov ah, 0x0E        
    int 0x10           
]], funcName, arg)
end

local function generatePubFunction(funcName, body)
    return string.format([[ 
%s: 
%s 
ret 
]], funcName, body)
end

local function generateConcatenation(varName, parts)
    local dataSegment = {}
    for _, part in ipairs(parts) do
        table.insert(dataSegment, string.format("db '%s'", part))
    end
    return string.format("%s: %s, 0", varName, table.concat(dataSegment, ", "))
end

local function generateArithmetic(operation, operand1, operand2)
    local operations = {
        ["+"] = "add",
        ["-"] = "sub",
        ["*"] = "mul",
        ["/"] = "div"
    }
    local assemblyOp = operations[operation]
    return string.format([[ 
    mov ax, %s     
    %s ax, %s      
]], operand1, assemblyOp, operand2)
end

local function generateInlineAssembly(asmCode)
    return string.format([[ 
; Inline Assembly Start 
%s 
; Inline Assembly End 
]], asmCode)
end

local function generateHalt()
    return [[ 
    hlt              
]]
end

local function generateCli()
    return [[ 
    cli              
]]
end

local function generateDiskRead(sector, count, buffer)
    return string.format([[ 
    mov ah, 0x02       
    mov al, %d         
    mov ch, 0          
    mov cl, %d         
    mov dh, 0          
    mov bx, %s         
    int 0x13          
]], count, sector, buffer)
end

local function generateDiskWrite(sector, count, buffer)
    return string.format([[ 
    mov ah, 0x03       
    mov al, %d         
    mov ch, 0          
    mov cl, %d         
    mov dh, 0          
    mov bx, %s         
    int 0x13          
]], count, sector, buffer)
end

local function generateImport(filePath, localName)
    local content = readFile(filePath)
    return string.format([[ 
; Importing module from %s as %s 
section .text 
%s 
]], filePath, localName, content)
end

local function generateUse(moduleName, funcName, localName)
    return string.format([[ 
    ; Using function %s from module %s 
    call %s_%s 
]], funcName, moduleName, localName, funcName)
end

local function generateSignature(signature, size)
    return string.format([[ 
times %d - ($ - $$) db 0  
dw 0x%X                   
]], size, signature)
end

local function generateOrigin(mode, origin)
    return string.format([[ 
[BITS %d]  
[ORG 0x%X]                   
]], mode, origin)
end

local function generateCode(input)
    local code = {}
    local signatureCode = ""

    addSection("text")
    addSection("data")

    addToSection("text", [[ 
global _start 

_start: 
]])

    addToSection("text", generateVgaBuffer())

    addToSection("data", [[ 
section .data 
]])

    if input:match("%[start%s*\"([^\"]+)\"%s*,%s*\"([^\"]+)\"%]") then
        local mode, origin = input:match('%[start%s*"([^"]+)"%s*,%s*"([^"]+)"%]')
        mode = tonumber(mode)
        origin = tonumber(origin)
        addToSection("text", generateOrigin(mode, origin))
    end

    local importPattern = "local%s+(%w+)%s*=%s*require%s*%('([^']+)'%)"
    for localName, filePath in input:gmatch(importPattern) do
        if localName and filePath then
            addToSection("text", generateImport(filePath, localName))
        end
    end

    local usePattern = "local%s+(%w+)%s*=%s*use%s+(%w+)%s*%.%s*(%w+)"
    for localName, moduleName, funcName in input:gmatch(usePattern) do
        if moduleName and funcName then
            addToSection("text", generateUse(moduleName, funcName, localName))
        end
    end

    local pubPattern = "pub%s+function%s+(%w+)%s*%(([^)]+)%)%s*(.-)end"
    for funcName, args, body in input:gmatch(pubPattern) do
        addToSection("text", generatePubFunction(funcName, body))
    end

    local concatPattern = "local%s+(%w+)%s*=%s*\"(.-)\"%s*..%s*\"(.-)\""
    local varName, concatStr1, concatStr2 = input:match(concatPattern)
    if varName and concatStr1 and concatStr2 then
        addToSection("data", generateConcatenation(varName, {concatStr1, concatStr2}))
    else
        local varPattern = "local%s+(%w+)%s*=%s*\"(.-)\""
        varName, varValue = input:match(varPattern)
        if varName and varValue then
            addToSection("data", generateVariable(varName, varValue))
        end
    end

    local arithPattern = "local%s+(%w+)%s*=%s*(%w+)%s*([%+%-/%*])%s*(%w+)"
    local resultVar, operand1, operator, operand2 = input:match(arithPattern)
    if resultVar and operand1 and operator and operand2 then
        addToSection("text", generateArithmetic(operator, operand1, operand2))
    end

    for asmCode in input:gmatch("asm%s*{(.-)}") do
        addToSection("text", generateInlineAssembly(asmCode))
    end

    for sector, count, buffer in input:gmatch("disk%.read%s*%((%d+),%s*(%d+),%s*(%w+)%)") do
        if sector and count and buffer then
            addToSection("text", generateDiskRead(sector, count, buffer))
        end
    end

    for sector, count, buffer in input:gmatch("disk%.write%s*%((%d+),%s*(%d+),%s*(%w+)%)") do
        if sector and count and buffer then
            addToSection("text", generateDiskWrite(sector, count, buffer))
        end
    end

    if input:match("halt%s*%(%s*%)") then
        addToSection("text", generateHalt())
    end

    if input:match("cli%s*%(%s*%)") then
        addToSection("text", generateCli())
    end

    if input:match("signature%s*%((%w+)%s*,%s*(%d+)%)") then
        local signature, size = input:match("signature%s*%((%w+)%s*,%s*(%d+)%)")
        addToSection("text", generateSignature(signature, size))
    end

    for _, section in pairs(sections) do
        code[#code + 1] = table.concat(section, "\n")
    end

    return table.concat(code, "\n\n")
end

local inputFilePath, outputFilePath = arg[1], arg[2]
if not inputFilePath or not outputFilePath then
    error("Usage: lua script.lua <inputFilePath> <outputFilePath>")
end

local inputContent = readFile(inputFilePath)
local generatedCode = generateCode(inputContent)
writeFile(outputFilePath, generatedCode)

print("Code generation complete! Output written to " .. outputFilePath)
