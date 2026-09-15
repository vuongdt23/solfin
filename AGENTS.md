# Development workflow

After each implementation change, regenerate and build the macOS app so it can be run directly from Xcode DerivedData:

```sh
xcodegen generate
xcodebuild -scheme solfin -configuration Debug -destination 'platform=macOS' build
```

The resulting app is typically available at:

```sh
open ~/Library/Developer/Xcode/DerivedData/solfin-*/Build/Products/Debug/Solfin.app
```

Use the actual DerivedData path printed or discovered after the build when multiple checkouts exist.
