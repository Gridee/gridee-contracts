# Gridee Smart Contracts

All contracts are deployed on **Lisk Sepolia** (Chain ID: 4202) and verified on [Blockscout](https://sepolia-blockscout.lisk.com/).

## Deployed Addresses

| Contract | Address |
|---|---|
| GrideeToken | `0x8D7fE0804425cfc0B827a88c5aD932749f92f096` |
| WalletFactory | `0x18D5E4334986853C89f9A2c5e2da7a1DBb6347ce` |
| PropertyRegistry | `0x7805B5941B259C673E1694240c4b0cBA029f345B` |
| EnergyLedger | `0x8911F55c05Ab28FF4bDade40aC78Ba3cb6BD204a` |
| RevenueDistributor | `0xaC760BDa41Ce51ff1adA67FD97A2C6502DB76c02` |

## Architecture

```
WhatsApp/USSD → Backend → Blockchain
                            │
                            ├── GrideeToken (ERC-20)
                            ├── WalletFactory (custodial wallet registry)
                            ├── PropertyRegistry (property management)
                            ├── EnergyLedger (mint, deduct, cut-off)
                            └── RevenueDistributor (revenue split)
```

All contracts use OpenZeppelin's `AccessControl`. The backend interacts with contracts via `OPERATOR_ROLE`. The deployer's `DEFAULT_ADMIN_ROLE` is renounced immediately after deployment — only the designated `admin` address (granted before renunciation) can perform admin functions like pausing or updating shares.

## Security Features

- **Pausable**: All contracts can be paused by `DEFAULT_ADMIN_ROLE` to halt operations during emergencies
- **ReentrancyGuard**: `RevenueDistributor.withdraw()` is protected against reentrancy attacks
- **Admin Renunciation**: Deployer renounces `DEFAULT_ADMIN_ROLE` post-deployment; a separate admin address is granted the role beforehand
- **isCutOff enforcement**: `EnergyLedger.mintTokens()` reverts if the tenant is cut off

---

## GrideeToken

**Type:** ERC-20 token  
**Name:** Gridee Energy Token  
**Symbol:** GRD  
**Decimals:** 18  
**Ratio:** 1 GRD = 1 kWh

### What It Does

The native token for the Gridee ecosystem. Tenants hold GRD to pay for energy consumption. The token is minted when tenants purchase energy and burned when energy is consumed. Only `EnergyLedger` and `RevenueDistributor` are granted `OPERATOR_ROLE` to mint/burn — no one else can change supply.

### Functions

#### `mint(address to, uint256 amount)` — `OPERATOR_ROLE`
Mints GRD tokens to the specified address. Called by EnergyLedger after a tenant payment is confirmed.

#### `burn(address account, uint256 amount)` — `OPERATOR_ROLE`
Burns GRD tokens from the specified address. Called by EnergyLedger when energy is consumed.

#### `transfer(address to, uint256 amount)` — public
Standard ERC-20 transfer. Tenants can transfer tokens between wallets.

#### `balanceOf(address account) → uint256` — public view
Returns the GRD balance of an account.

---

## WalletFactory

### What It Does

Maps user phone hashes to their custodial EVM wallet addresses. When a user registers via WhatsApp or USSD, the backend generates a random wallet, stores the private key securely, and records the address on-chain. Phone numbers are never stored on-chain — only their `keccak256` hash.

### Functions

#### `registerLandlord(bytes32 phoneHash, address wallet)` — `OPERATOR_ROLE`
Registers a landlord's wallet address against their phone hash.

**Parameters:**
- `phoneHash` — `keccak256(abi.encodePacked(phoneNumber))`
- `wallet` — the generated EVM wallet address

**Emits:** `LandlordRegistered(operator, phoneHash, wallet)`

#### `registerTenant(bytes32 phoneHash, address wallet, bytes32 propertyCode)` — `OPERATOR_ROLE`
Registers a tenant's wallet address against their phone hash and links them to a property.

**Parameters:**
- `phoneHash` — `keccak256(abi.encodePacked(phoneNumber))`
- `wallet` — the generated EVM wallet address
- `propertyCode` — the property code the tenant is joining

**Emits:** `TenantRegistered(operator, phoneHash, wallet, propertyCode)`

#### `getLandlordWallet(bytes32 phoneHash) → address` — public view
Returns the wallet address for a registered landlord.

#### `getTenantWallet(bytes32 phoneHash) → address` — public view
Returns the wallet address for a registered tenant.

#### `getTenantProperty(bytes32 phoneHash) → bytes32` — public view
Returns the property code a tenant is registered under.

#### `isWalletRegistered(address wallet) → bool` — public view
Checks if a wallet address has already been assigned to any user. Prevents wallet reuse.

---

## PropertyRegistry

### What It Does

Stores property details on-chain. Landlords register properties through the bot, and the backend records the property code, flat count, location, and landlord wallet. Property codes are generated off-chain (e.g., `GRD-LAG-0045`) and converted to `bytes32` before on-chain storage.

### Functions

#### `registerProperty(bytes32 code, address landlordWallet, uint8 flatCount, string location)` — `OPERATOR_ROLE`
Registers a new property.

**Parameters:**
- `code` — property code as `bytes32` (e.g., `ethers.encodeBytes32String("GRD-LAG-0045")`)
- `landlordWallet` — the landlord's wallet address
- `flatCount` — number of flats/units in the property
- `location` — property location string

**Emits:** `PropertyRegistered(operator, landlord, code, flatCount)`

#### `updateProperty(bytes32 code, uint8 newFlatCount, string newLocation)` — `OPERATOR_ROLE`
Updates a property's flat count, location, or both. Use `0` for `newFlatCount` or `""` for `newLocation` to skip updating that field.

**Parameters:**
- `code` — property code
- `newFlatCount` — new flat count (0 to skip)
- `newLocation` — new location (empty string to skip)

**Emits:** `PropertyFlatCountUpdated(code, oldFlatCount, newFlatCount)` and/or `PropertyLocationUpdated(code, oldLocation, newLocation)`

#### `getProperty(bytes32 code) → Property` — view
Returns property details. Accessible only by the property's landlord or an operator.

**Returns struct:**
```solidity
struct Property {
    uint8 flatCount;
    string location;
    bool isActive;
    uint40 createdAt;
}
```

#### `deactivateProperty(bytes32 code)` — `DEFAULT_ADMIN_ROLE`
Deactivates a property. Only the contract admin can do this.

**Emits:** `PropertyDeactivated(admin, code, landlord)`

#### `getPropertiesByLandlord(address landlordWallet) → Property[]` — public view
Returns all properties registered to a landlord.

#### `getPropertyCodesByLandlord(address landlordWallet) → bytes32[]` — public view
Returns all property codes registered to a landlord.

---

## EnergyLedger

### What It Does

Manages token minting and burning for energy transactions. When a tenant pays for energy, the backend calls `mintTokens` to issue GRD. When energy is consumed (via the HAL consumption simulator), the backend calls `deductTokens` to burn GRD. Also manages tenant cut-off status — when a tenant's balance hits zero, they are cut off from energy access.

### Functions

#### `mintTokens(address tenantWallet, uint256 amount)` — `OPERATOR_ROLE`
Mints GRD tokens to a tenant's wallet after payment confirmation. Reverts if the tenant is cut off (`isCutOff` is true).

**Parameters:**
- `tenantWallet` — the tenant's wallet address
- `amount` — amount of GRD to mint (in wei, 18 decimals)

**Emits:** `TokensMinted(tenant, amount)`

#### `deductTokens(address tenantWallet, uint256 amount)` — `OPERATOR_ROLE`
Burns GRD tokens from a tenant's wallet to reflect energy consumption. Reverts if the tenant has insufficient balance.

**Parameters:**
- `tenantWallet` — the tenant's wallet address
- `amount` — amount of GRD to burn (in wei, 18 decimals)

**Emits:** `TokensDeducted(tenant, amount)`

#### `getBalance(address tenantWallet) → uint256` — public view
Returns a tenant's GRD balance. Equivalent to calling `GrideeToken.balanceOf()`.

#### `setCutOff(address tenantWallet, bool status)` — `DEFAULT_ADMIN_ROLE`
Sets the cut-off status for a tenant. When `true`, the tenant's energy access is disabled.

**Emits:** `CutOffUpdated(admin, tenant, status)`

#### `isCutOff(address tenantWallet) → bool` — public view
Returns whether a tenant is cut off.

#### `token() → IGrideeToken` — public view
Returns the GrideeToken contract interface.

---

## RevenueDistributor

### What It Does

Splits revenue from tenant payments between the landlord, platform, and operations reserve. When a payment is confirmed, `distributeRevenue` is called with the total NGN-equivalent GRD amount. The landlord's share accumulates in `pendingWithdrawals` (pull pattern), while the platform and ops shares are transferred immediately. Protected by `ReentrancyGuard` on withdrawals and `Pausable` for emergency stops.

### Default Split (Basis Points)

| Party | BPS | Percentage |
|---|---|---|
| Landlord | 1800 | 18% |
| Platform | 900 | 9% |
| Ops Reserve | 7300 | 73% |

### Functions

#### `distributeRevenue(bytes32 propertyCode, address landlordWallet, uint256 totalAmount)` — `OPERATOR_ROLE`
Distributes a payment across landlord, platform, and ops shares.

**Parameters:**
- `propertyCode` — the property code the payment is for
- `landlordWallet` — the landlord's wallet address
- `totalAmount` — total GRD amount (in wei, 18 decimals)

**Emits:** `RevenueDistributed(propertyCode, landlord, totalAmount, landlordShare, platformShare, opsShare)`

#### `withdraw()` — public
Allows a landlord to withdraw their accumulated GRD share. Protected by `ReentrancyGuard`. Transfers the full `pendingWithdrawals` balance to `msg.sender` and resets it to zero.

**Emits:** `WithdrawalClaimed(landlord, amount)`

#### `updateShares(uint256 newLandlordBPS, uint256 newPlatformBPS)` — `DEFAULT_ADMIN_ROLE`
Updates the revenue split percentages. The sum of both values must not exceed 10,000 (100%). The remainder goes to the ops reserve.

**Parameters:**
- `newLandlordBPS` — landlord share in basis points
- `newPlatformBPS` — platform share in basis points

**Emits:** `SharesUpdated(newLandlordBPS, newPlatformBPS)`

#### `updateWallets(address newPlatformWallet, address newOpsWallet)` — `DEFAULT_ADMIN_ROLE`
Updates the destination wallets for platform and ops shares.

**Parameters:**
- `newPlatformWallet` — new platform wallet address
- `newOpsWallet` — new ops wallet address

**Emits:** `WalletsUpdated(newPlatformWallet, newOpsWallet)`

#### `pendingWithdrawals(address landlord) → uint256` — public view
Returns the accumulated GRD balance available for a landlord to withdraw.

---

## Backend Integration

The backend interacts with contracts using the platform wallet's private key. Example flow:

```typescript
import { ethers } from "ethers";

const provider = new ethers.JsonRpcProvider(process.env.LISK_SEPOLIA_RPC_URL);
const signer = new ethers.Wallet(process.env.PRIVATE_KEY, provider);

const energyLedger = new ethers.Contract(
  process.env.CONTRACT_ENERGYLEDGER,
  EnergyLedgerABI,
  signer
);

const revenueDistributor = new ethers.Contract(
  process.env.CONTRACT_REVENUEDISTRIBUTOR,
  RevenueDistributorABI,
  signer
);

// After Flutterwave payment confirmed
async function processPayment(tenantWallet: string, grdAmount: bigint, propertyCode: string, landlordWallet: string) {
  // 1. Mint tokens to tenant
  await energyLedger.mintTokens(tenantWallet, grdAmount);

  // 2. Mint tokens to RevenueDistributor (it needs balance to distribute platform/ops shares)
  await token.mint(revenueDistributorAddress, grdAmount);

  // 3. Distribute revenue (pulls from RevenueDistributor balance)
  await revenueDistributor.distributeRevenue(
    ethers.encodeBytes32String(propertyCode),
    landlordWallet,
    grdAmount
  );
}
```
