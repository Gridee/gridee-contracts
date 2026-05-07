# Gridee Smart Contracts

All contracts are deployed on **Lisk Sepolia** (Chain ID: 4202) and verified on [Blockscout](https://sepolia-blockscout.lisk.com/).

## Deployed Addresses

| Contract | Address | Blockscout |
|---|---|---|
| GrideeToken | `0x3D45a4d1953490Bc094E970177d1e73D9a72F781` | [View](https://sepolia-blockscout.lisk.com/address/0x3D45a4d1953490Bc094E970177d1e73D9a72F781) |
| PropertyRegistry | `0x3b0Ec16b27f7d3ecE4b959507Dc6a6Ab2790d61f` | [View](https://sepolia-blockscout.lisk.com/address/0x3b0Ec16b27f7d3ecE4b959507Dc6a6Ab2790d61f) |
| EnergyLedger | `0x532FAC26C1ee8485c5f55fA379036F9d5C024482` | [View](https://sepolia-blockscout.lisk.com/address/0x532FAC26C1ee8485c5f55fA379036F9d5C024482) |

### USDC on Lisk Sepolia

| Token | Address |
|---|---|
| USDC | `0x83d90d759849eE558E1F05289e6c4a46Ac8Aa037` |

## Architecture

```
WhatsApp → Backend → Privy → Blockchain
                            │
                            ├── GrideeToken (ERC-20 + USDC vault)
                            ├── PropertyRegistry (property + tenant capacity)
                            └── EnergyLedger (deduct/burn, cut-off)
```

All contracts use OpenZeppelin's `AccessControl`. The backend interacts with contracts via `OPERATOR_ROLE`. The deployer's `DEFAULT_ADMIN_ROLE` is renounced immediately after deployment — only the designated `admin` address (granted before renunciation) can perform admin functions like pausing or updating shares.

## Security Features

- **Pausable**: All contracts can be paused by `DEFAULT_ADMIN_ROLE` to halt operations during emergencies
- **ReentrancyGuard**: `GrideeToken.depositUSDC()` and `purchaseTokens()` are protected against reentrancy
- **Admin Renunciation**: Deployer renounces `DEFAULT_ADMIN_ROLE` post-deployment; a separate admin address is granted the role beforehand
- **USDC Vault**: Tenants deposit USDC into GrideeToken contract — no withdrawal function exists, enforcing FR-T05 at contract level
- **GRD Transfer Restriction**: GRD tokens can only be transferred to `address(0)` (burn) or `EnergyLedger` — tenants cannot trade or gift tokens
- **Tenant Capacity**: PropertyRegistry enforces flat count limits on-chain — registration reverts when property is full

---

## GrideeToken

**Type:** ERC-20 token + USDC vault  
**Name:** Gridee Token  
**Symbol:** GRD  
**Decimals:** 18  
**Ratio:** 1 GRD = 1 kWh (priced in USDC)

### What It Does

The native token for the Gridee ecosystem. Tenants deposit USDC into the contract (vault), then call `purchaseTokens()` to convert USDC to GRD. Revenue is split atomically: landlord share + platform share + ops share are sent in USDC, and GRD is minted to the tenant in the same transaction.

GRD tokens **cannot be transferred** except to `EnergyLedger` (for burning). This prevents secondary market trading and ensures GRD is only used for energy consumption.

### Functions

#### `depositUSDC(uint256 amount)` — public
Deposits USDC into the vault and credits the tenant's internal balance. USDC is locked — there is no withdrawal function.

**Parameters:**
- `amount` — USDC amount (6 decimals)

**Emits:** `USDCDeposited(tenant, amount)`

#### `purchaseTokens(uint256 usdcAmount, address landlord)` — public
Converts USDC from the tenant's vault balance to GRD tokens. Atomically splits USDC revenue and mints GRD.

**Parameters:**
- `usdcAmount` — USDC amount to convert (6 decimals)
- `landlord` — landlord wallet address for revenue split

**Emits:** `TokensPurchased(tenant, landlord, usdcAmount, grdAmount, landlordShare, platformShare, opsShare)`

#### `tenantUSDCBalance(address tenant) → uint256` — public view
Returns the tenant's locked USDC balance in the vault.

#### `burn(address account, uint256 amount)` — `BURNER_ROLE`
Burns GRD tokens from the specified account. Called by `EnergyLedger` when energy is consumed.

#### `setPrice(uint256 newPricePerGRD)` — `DEFAULT_ADMIN_ROLE`
Sets the price per GRD token in USDC (6 decimals).

#### `updateShares(uint256 newLandlordBPS, uint256 newPlatformBPS)` — `DEFAULT_ADMIN_ROLE`
Updates the revenue split percentages. Sum must not exceed 10,000 (100%).

#### `updateWallets(address newPlatformWallet, address newOpsWallet)` — `DEFAULT_ADMIN_ROLE`
Updates the destination wallets for platform and ops shares.

---

## PropertyRegistry

### What It Does

Stores property details and manages tenant capacity on-chain. Landlords register properties through the bot, and the backend records the property code, flat count, location, and landlord wallet. Tenant registration decrements available flats — reverts when property is at capacity.

### Functions

#### `registerProperty(bytes32 code, address landlordWallet, uint8 flatCount, string location)` — `OPERATOR_ROLE`
Registers a new property.

**Parameters:**
- `code` — property code as `bytes32`
- `landlordWallet` — the landlord's wallet address
- `flatCount` — number of flats/units
- `location` — property location string

**Emits:** `PropertyRegistered(operator, landlord, code, flatCount)`

#### `registerTenant(bytes32 propertyCode, address tenantWallet)` — `OPERATOR_ROLE`
Registers a tenant under a property. Decrements available flat count. Reverts if property is at capacity or tenant is already registered.

**Parameters:**
- `propertyCode` — the property code
- `tenantWallet` — the tenant's wallet address

**Emits:** `TenantRegistered(operator, propertyCode, tenant)`

#### `deregisterTenant(bytes32 propertyCode, address tenantWallet)` — `OPERATOR_ROLE`
Removes a tenant from a property. Increments available flat count.

**Parameters:**
- `propertyCode` — the property code
- `tenantWallet` — the tenant's wallet address

**Emits:** `TenantDeregistered(operator, propertyCode, tenant)`

#### `getProperty(bytes32 code) → Property` — view
Returns property details. Accessible only by the property's landlord or an operator.

**Returns struct:**
```solidity
struct Property {
    uint8 flatCount;
    uint8 occupiedFlats;
    string location;
    bool isActive;
    uint40 createdAt;
}
```

#### `getAvailableFlats(bytes32 propertyCode) → uint8` — public view
Returns the number of available flats for a property.

#### `getTenantProperty(address tenantWallet) → bytes32` — public view
Returns the property code a tenant is registered under.

#### `deactivateProperty(bytes32 code)` — `DEFAULT_ADMIN_ROLE`
Deactivates a property.

---

## EnergyLedger

### What It Does

Manages GRD token burning for energy consumption. Called by the HAL (or mock consumption cron) to deduct tokens when energy is used. Also manages tenant cut-off status — when a tenant's balance hits zero, they are cut off from energy access.

### Functions

#### `deductTokens(address tenantWallet, uint256 amount)` — `OPERATOR_ROLE`
Burns GRD tokens from a tenant's wallet to reflect energy consumption. Reverts if the tenant has insufficient balance or is cut off.

**Parameters:**
- `tenantWallet` — the tenant's wallet address
- `amount` — amount of GRD to burn (in wei, 18 decimals)

**Emits:** `TokensDeducted(tenant, amount)`

#### `getBalance(address tenantWallet) → uint256` — public view
Returns a tenant's GRD balance.

#### `setCutOff(address tenantWallet, bool status)` — `DEFAULT_ADMIN_ROLE`
Sets the cut-off status for a tenant. When `true`, `deductTokens()` reverts for this tenant.

**Emits:** `CutOffUpdated(admin, tenant, status)`

#### `isCutOff(address tenantWallet) → bool` — public view
Returns whether a tenant is cut off.

---

## Revenue Distribution

Every `purchaseTokens()` call triggers an **atomic** revenue split inside the GrideeToken contract:

| Party | BPS | Percentage |
|---|---|---|
| Landlord | 1800 | 18% |
| Platform | 900 | 9% |
| Ops Reserve | 7300 | 73% |

USDC is transferred directly to each party's wallet in the same transaction. No separate distribution step is needed.

---

## Backend Integration

The backend interacts with contracts via Privy-signed transactions. Example flow:

```typescript
import { ethers } from "ethers";

const provider = new ethers.JsonRpcProvider(process.env.LISK_SEPOLIA_RPC_URL);
const signer = new ethers.Wallet(process.env.PRIVATE_KEY, provider);

const token = new ethers.Contract(
  process.env.CONTRACT_GRIDEETOKEN,
  GrideeTokenABI,
  signer
);

const energyLedger = new ethers.Contract(
  process.env.CONTRACT_ENERGYLEDGER,
  EnergyLedgerABI,
  signer
);

const propertyRegistry = new ethers.Contract(
  process.env.CONTRACT_PROPERTYREGISTRY,
  PropertyRegistryABI,
  signer
);

// After Yellow Card onramp confirmed (or manual USDC deposit for demo)
async function depositAndBuy(tenantWallet: string, usdcAmount: bigint, landlordWallet: string) {
  // 1. Tenant deposits USDC into vault
  await token.connect(tenantSigner).depositUSDC(usdcAmount);

  // 2. Tenant purchases GRD — revenue splits atomically
  await token.connect(tenantSigner).purchaseTokens(usdcAmount, landlordWallet);
}

// HAL consumption cron
async function consumeEnergy(tenantWallet: string, kwhAmount: bigint) {
  await energyLedger.deductTokens(tenantWallet, kwhAmount);
}

// Register tenant (with capacity check)
async function registerTenant(propertyCode: string, tenantWallet: string) {
  await propertyRegistry.registerTenant(
    ethers.encodeBytes32String(propertyCode),
    tenantWallet
  );
}
```

---

## Deployment

```bash
# Set environment variables
cp .env.example .env
# Edit .env with your values

# Deploy to Lisk Sepolia
forge script script/Deploy.s.sol --rpc-url $LISK_SEPOLIA_RPC_URL --broadcast --verifier blockscout --verifier-url https://sepolia-blockscout.lisk.com/api --chain 4202
```

### Required Environment Variables

| Variable | Description |
|---|---|
| `PRIVATE_KEY` | Deployer wallet private key |
| `OPERATOR_ADDRESS` | Backend operator address |
| `USDC_ADDRESS` | USDC contract address on Sepolia |
| `PLATFORM_WALLET` | Platform revenue wallet |
| `OPS_WALLET` | Operations reserve wallet |
| `PRICE_PER_GRD` | Price per GRD in USDC (6 decimals, e.g. 10000 = $0.01) |
| `LANDLORD_SHARE_BPS` | Landlord share in basis points (e.g. 1800 = 18%) |
| `PLATFORM_SHARE_BPS` | Platform share in basis points (e.g. 900 = 9%) |
