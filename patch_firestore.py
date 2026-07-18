import re

files_to_patch = [
    'lib/screens/edit_profile_screen.dart',
    'lib/screens/inviter_selection_screen.dart',
    'lib/screens/main_hall_screen.dart',
    'lib/screens/onboarding_screen.dart',
]

for file in files_to_patch:
    with open(file, 'r') as f:
        content = f.read()

    # We want to replace "await FirebaseFirestore.instance" with "FirebaseFirestore.instance"
    # ONLY when it is followed by .set( or .update(
    # A bit complex with regex over multiple lines, so we can just blindly replace
    # "await FirebaseFirestore.instance.collection('users').doc(user.uid).set" and similar
    # Or simply:
    content = content.replace("await FirebaseFirestore.instance.collection('users').doc(user!.uid).update({'photoURL': url});", "FirebaseFirestore.instance.collection('users').doc(user!.uid).update({'photoURL': url});")
    content = content.replace("await FirebaseFirestore.instance\n              .collection('users')\n              .doc(user!.uid)\n              .update({'photoURL': url});", "FirebaseFirestore.instance\n              .collection('users')\n              .doc(user!.uid)\n              .update({'photoURL': url});")
    
    content = content.replace("await FirebaseFirestore.instance\n                .collection('users')\n                .doc(user!.uid)\n                .set({", "FirebaseFirestore.instance\n                .collection('users')\n                .doc(user!.uid)\n                .set({")
    
    content = content.replace("await FirebaseFirestore.instance.collection('users').doc(user.uid).set({", "FirebaseFirestore.instance.collection('users').doc(user.uid).set({")
    content = content.replace("await FirebaseFirestore.instance.collection('users').doc(user.uid).update(", "FirebaseFirestore.instance.collection('users').doc(user.uid).update(")
    content = content.replace("await FirebaseFirestore.instance\n                .collection('users')\n                .doc(user.uid)\n                .set(", "FirebaseFirestore.instance\n                .collection('users')\n                .doc(user.uid)\n                .set(")

    with open(file, 'w') as f:
        f.write(content)

print("Optimistic UI applied to Firestore writes.")
