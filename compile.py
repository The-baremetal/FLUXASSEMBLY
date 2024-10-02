import re
import argparse

class ASTNode:
    def __init__(self, node_type, value=None):
        self.node_type = node_type
        self.value = value
        self.children = []

    def add_child(self, child):
        self.children.append(child)

class LuaASMParser:
    def __init__(self):
        self.ast = ASTNode("program")
        self.architecture = None
        self.directives = {"pad": None, "sign": None, "start": None}
        self.functions = {}
        self.current_function = None
        self.code_outside_functions = []  
        self.imports = {}  
        self.inline_asm = []  

    def parse(self, code):
        lines = code.strip().splitlines()
        for line in lines:
            line = line.strip()
            if not line:
                continue

            if line.startswith("import"):
                self._parse_import_definition(line)
            elif line.startswith("#!arch["):
                self._parse_architecture(line)
            elif line.startswith("#!["):
                self._parse_directive(line)
            elif line.startswith("function"):
                self._parse_function_definition(line)
            elif line == "end":
                self._end_function_definition()
            elif re.match(r'^\w+\(.*\)$', line):
                self._parse_function_call(line)
            elif line.startswith("asm(") and line.endswith(")"):
                self._parse_inline_asm(line)
            else:
                self._parse_executable_code(line)

    def _parse_import_definition(self, line):
        single_import = re.match(r'import (\w+) from (\w+)', line)
        multi_import = re.match(r'import \[(.+)\] from (\w+)', line)
        local_import = re.match(r'local (\w+) = import (\w+) from (\w+)', line)

        if single_import:
            func_name = single_import.group(1)
            module_name = single_import.group(2)
            self.imports[func_name] = module_name
        elif multi_import:
            functions = [f.strip() for f in multi_import.group(1).split(",")]
            module_name = multi_import.group(2)
            for func in functions:
                self.imports[func] = module_name
        elif local_import:
            local_var = local_import.group(1)
            func_name = local_import.group(2)
            module_name = local_import.group(3)
            self.imports[local_var] = f"{module_name}.{func_name}"  
        else:
            raise SyntaxError(f"Invalid import statement: {line}")

    def _parse_architecture(self, line):
        match = re.match(r'#\!arch\[(.+)\]', line)
        if match:
            self.architecture = match.group(1)
        else:
            raise SyntaxError(f"Invalid architecture definition: {line}")

    def _parse_inline_asm(self, line):

        if line.startswith("asm(") and line.endswith(")"):
            print("LOAD")
            asm_code = line[4:-1].strip()  
            self.inline_asm.append(asm_code)  
        else:
            raise SyntaxError(f"Invalid inline assembly format: {line}")

    def _parse_directive(self, line):
        match = re.match(r'#\!\[(start|pad|sign)\((0x[a-fA-F0-9]+|\d+)\)\]', line)
        if match:
            directive = match.group(1)
            value = match.group(2)
            self.directives[directive] = value
        else:
            raise SyntaxError(f"Invalid directive format: {line}")

    def _parse_function_definition(self, line):
        match = re.match(r'function (\w+)\((.*)\)', line)
        if match:
            func_name = match.group(1)
            params = [p.strip() for p in match.group(2).split(",")] if match.group(2) else []
            self.current_function = {"name": func_name, "params": params, "body": []}
        else:
            raise SyntaxError(f"Invalid function definition: {line}")

    def _end_function_definition(self):
        if self.current_function:
            self.functions[self.current_function["name"]] = self.current_function
            self.current_function = None

    def _parse_function_call(self, line):
        func_call = line.strip()
        if self.current_function:
            self.current_function["body"].append(func_call)
        else:
            self.code_outside_functions.append(func_call)

    def _parse_executable_code(self, line):
        self.code_outside_functions.append(line.strip())

    def generate_code(self):
        output = []
        if self.architecture:
            if self.architecture.lower() == 'x86':
                bits = "BITS 32"
            elif self.architecture.lower() == 'x64':
                bits = "BITS 64"
            elif self.architecture.lower() == 'x16':
                bits = "BITS 16"
            else:
                bits = "BITS 32"

            output.append(bits)

        if self.directives["start"]:
            output.append(f"ORG {self.directives['start']}")

        output.append("_start:")

        output.append("  push 2")   
        output.append("  push 3")   
        output.append("  push 5")   
        output.append("  call add")  
        output.append("  add esp, 12") 

        for line in self.code_outside_functions:
            output.append(f"  {line}")  

        for func in self.functions.values():
            output.append(f"{func['name']}:")
            output.append("  mov eax, [esp + 4]")   
            output.append("  add eax, [esp + 8]")   
            output.append("  add eax, [esp + 12]")  
            output.append("  ret")                   

        for asm in self.inline_asm:
            output.append(self._parse_inline_asm(asm))  

        if self.directives["pad"]:
            padding_value = self.directives["pad"]
            output.append(f"  times {padding_value} - ($ - $$) db 0")  

        if self.directives["sign"]:
            output.append(f"  dw {self.directives['sign']}  ; Signature")

        return "\n".join(output)

def main(input_file, output_path):
    with open(input_file, 'r') as f:
        luaasm_code = f.read()

    parser = LuaASMParser()
    parser.parse(luaasm_code)
    output_code = parser.generate_code()

    with open(output_path, 'wb') as f:
        f.write(output_code.encode('utf-8'))

    print(f"Output written to {output_path}")

if __name__ == "__main__":
    parser = argparse.ArgumentParser(description='LuaASM Parser')
    parser.add_argument('input_file', type=str, help='Input LuaASM file to parse')
    parser.add_argument('output_path', type=str, help='Output path for the generated assembly code')

    args = parser.parse_args()
    main(args.input_file, args.output_path)
