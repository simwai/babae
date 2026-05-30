def find_mismatch(filepath):
    with open(filepath, 'r') as f:
        lines = f.readlines()

    stack = []
    for i, line in enumerate(lines):
        for j, char in enumerate(line):
            if char == '{':
                stack.append((i+1, j+1))
            elif char == '}':
                if not stack:
                    print(f"Extra '}}' at line {i+1}, col {j+1}")
                else:
                    stack.pop()
    for line, col in stack:
        print(f"Unclosed '{{' at line {line}, col {col}")

if __name__ == "__main__":
    import sys
    find_mismatch(sys.argv[1])
