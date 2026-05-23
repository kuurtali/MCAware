import re

with open('index.html', 'r', encoding='utf-8') as f:
    html = f.read()

# Find the script block
script_match = re.search(r'<script>(.*?)</script>', html, flags=re.DOTALL)

if script_match:
    bad_js = script_match.group(1)
    
    # We have a nested 'document.addEventListener'
    # Let's fix the bad_js by simply removing the second document.addEventListener
    parts = bad_js.split("document.addEventListener('DOMContentLoaded', () => {")
    if len(parts) >= 3:
        # Reconstruct with only the first one
        fixed_js = parts[0] + "document.addEventListener('DOMContentLoaded', () => {" + parts[1] + parts[2]
        
        # Now replace the bad JS with the fixed JS in the HTML
        html = html.replace(bad_js, fixed_js)
        
        with open('index.html', 'w', encoding='utf-8') as f:
            f.write(html)
        print("Successfully fixed the JavaScript syntax error in index.html.")
    else:
        print("Couldn't find the nested addEventListener. Parts:", len(parts))
else:
    print("Could not find the script block.")
