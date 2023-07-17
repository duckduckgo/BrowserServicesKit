# Secure Vault Restructuring Notes

### Before

```mermaid
flowchart TD

    subgraph BrowserServicesKit
        common(Common Module)
        bsk("BrowserServicesKit Module
             • SecureVault
             • SecureVaultManager
             • SecureVaultFactory
             • SecureVaultCryptoProvider
             • SecureVaultDatabaseProvider
             • SecureVaultKeyStoreProvider
             • SecureVaultError
             • SecureVaultModels
             • GRDBExtensions
             • CreditCardValidation")

        common --> bsk
    end

    ios(iOS Client)
    macos(macOS Client)

    BrowserServicesKit --> ios
    BrowserServicesKit --> macos
```

### After
