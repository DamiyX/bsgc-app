import re

with open('lib/widgets/add_member_sheet.dart', 'r') as f:
    content = f.read()

# 1. Add TextField in UI
search_ui = '''                  ],
                ),
              ),

              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                child: TextField(
                  decoration: InputDecoration(
                    hintText: 'Search contacts...',
                    prefixIcon: const Icon(Icons.search),
                    filled: true,
                    fillColor: Colors.grey[100],
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide.none,
                    ),
                    contentPadding: const EdgeInsets.symmetric(vertical: 0),
                  ),
                  onChanged: (val) {
                    setState(() {
                      _searchQuery = val.toLowerCase();
                    });
                  },
                ),
              ),

'''

content = content.replace('''                  ],
                ),
              ),''', search_ui, 1)

# 2. Add filtering to the map functions
filter_logic_on = '''_onPlatformContacts.where((c) => (c['name'] as String).toLowerCase().contains(_searchQuery)).map('''
content = content.replace('''_onPlatformContacts.map(''', filter_logic_on, 1)

filter_logic_off = '''_offPlatformContacts.where((c) => (c['name'] as String).toLowerCase().contains(_searchQuery)).map('''
content = content.replace('''_offPlatformContacts.map(''', filter_logic_off, 1)

# 3. Use local contact name if available instead of forcing displayName
contact_name_logic = "u['displayName'] != null && (u['displayName'] as String).isNotEmpty ? u['displayName'] : name"
contact_name_replacement = "name.isNotEmpty ? name : (u['displayName'] != null && (u['displayName'] as String).isNotEmpty ? u['displayName'] : 'Unknown')"
content = content.replace(contact_name_logic, contact_name_replacement)

with open('lib/widgets/add_member_sheet.dart', 'w') as f:
    f.write(content)

print("Modifications applied successfully.")
