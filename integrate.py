import sys

def integrate(filepath, input_file, render_file):
    with open(filepath, 'r') as f:
        content = f.read()
    with open(input_file, 'r') as f:
        input_logic = f.read()
    with open(render_file, 'r') as f:
        render_logic = f.read()

    # Replace Start-InputThread through Read-NextInputEvent
    import re
    content = re.sub(r'function Start-InputThread \{.*?function Read-NextInputEvent \{.*?return \[PSCustomObject\]@\{ Kind=\'Key\'; KeyInfo=\(Make-KeyInfo \$ch \$ck 0\) \}\n\}',
                     input_logic, content, flags=re.DOTALL)

    # Replace Render-Frame
    content = re.sub(r'function Render-Frame \{.*?Out-Flush \$dirty\.ToString\(\)\n\}',
                     render_logic, content, flags=re.DOTALL)

    with open(filepath, 'w') as f:
        f.write(content)

integrate('babae.ps1', 'input_logic.ps1', 'render_logic.ps1')
