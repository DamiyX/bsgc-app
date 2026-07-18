import os
import re

def fix_const_errors(directory):
    for root, dirs, files in os.walk(directory):
        for file in files:
            if file.endswith('.dart'):
                filepath = os.path.join(root, file)
                with open(filepath, 'r', encoding='utf-8') as f:
                    content = f.read()

                # Regex to find 'const ' followed by anything up to 'Theme.of' on the same line
                new_content = re.sub(r'const\s+([^;\n]*?Theme\.of)', r'\1', content)
                
                if new_content != content:
                    with open(filepath, 'w', encoding='utf-8') as f:
                        f.write(new_content)
                    print(f"Updated {filepath}")

if __name__ == '__main__':
    fix_const_errors('lib')
