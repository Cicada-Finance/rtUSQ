# rtUSQ 智能合约安全审计报告（GPT 审计）

## 1. 报告信息

| 项目       | 内容                                                        |
| ---------- | ----------------------------------------------------------- |
| 审计对象   | rtUSQ 独立仓库                                              |
| 审计方     | OpenAI GPT（Codex）                                         |
| 审计性质   | AI 辅助代码安全审查                                         |
| 审计日期   | 2026-08-14                                                  |
| 复审日期   | 2026-08-14                                                  |
| 基准提交   | `54b8184` 加本次同步变更                                    |
| 审计方式   | 人工代码审查、资产流/权限流分析、边界条件推演、现有测试验证 |
| 编译环境   | Hardhat；Solidity 0.8.7 与 0.8.20                           |
| 自动化工具 | 未运行 Slither（当前环境未安装）                            |

本报告只覆盖下列当前工作区文件：

- `contracts/rtUSQ.sol`
- `contracts/rtUSQVault.sol`
- `contracts/rtUSQRebase.sol`
- `contracts/WrtUSQ.sol`（合约名 `WrappedRtUSQ`）

为判断集成影响，本次同时阅读了直接接口、自定义 `Ownable` / `ReentrancyGuard`、OpenZeppelin ERC4626 实现，以及相关测试和
`rtBTC` 的份额换算保护。外部 Router、WithdrawHelper、预言机、链上部署参数、私钥管理和前端不在正式审计范围内。

## 2. 执行摘要

审计共记录 10 项：

| 严重程度      | 数量 |
| ------------- | ---: |
| Critical      |    0 |
| High          |    1 |
| Medium        |    4 |
| Low           |    3 |
| Informational |    2 |

复审后的处置状态：

| 状态           | 数量 | 对应发现                                 |
| -------------- | ---: | ---------------------------------------- |
| 已修复         |    3 | M-04、L-01、I-02                         |
| 风险已接受     |    7 | H-01、M-01、M-02、M-03、L-02、L-03、I-01 |
| 未处置技术问题 |    0 | -                                        |

M-04、L-01 和 I-02 已完成代码修复与回归验证。其余发现经项目方确认属于预期业务、托管及权限模型，报告保留其风险描述，但不
再列为待修复项。风险接受不代表风险消失；部署和运营方仍需确保 owner、admin、assetManager 等受信任角色符合既定治理假设。

## 3. 系统与信任模型

### 3.1 资产流

1. 用户调用 `rtUSQVault.invest(amount)`。
2. Vault 将 `tokenUsd` 直接转给 `assetManager`，随后按原始数量 1:1 铸造 rtUSQ。
3. `rtUSQRebase` 的 admin 可按时间间隔触发正向 rebase；rtUSQ owner 本身也能直接调用任意正负 rebase。
4. 用户调用 `redeem(amount)` 销毁 rtUSQ，并在 `userAsset` 中形成等额结算债权。
5. 资产需由运营方另行转入 Vault，用户才可调用 `withdraw()` 取得 `tokenUsd`。
6. 用户可把 rtUSQ 存入 `WrappedRtUSQ`，取得非 rebase 的 ERC4626 份额。

### 3.2 特权角色

| 角色               | 主要能力                                                           |
| ------------------ | ------------------------------------------------------------------ |
| rtUSQ owner        | 初始化 Vault、修改 monetaryPolicy、直接执行任意正负 rebase         |
| Vault owner        | 修改结算币、admin 和 assetManager                                  |
| Vault admin        | 开关 invest/redeem/withdraw、任意修改 maxSupply 与 totalSubscribed |
| Vault assetManager | 接收所有投资资产、提取 Vault 内任意 ERC20/原生币                   |
| Rebase owner       | 修改 admin、rebase 上限和时间间隔、提取合约资产                    |
| Rebase admin       | 在当前参数限制下执行正向 rebase                                    |
| WrappedRtUSQ owner | 提取 wrapper 内任意 ERC20/原生币，包括 ERC4626 底层资产            |

这些角色应被视为完全受信任角色。任一 owner、admin 或 assetManager 私钥泄露，都可能导致供应失控、结算资产替换、流动性被提
走或用户无法赎回。

## 4. 审计发现

### [H-01] 特权救援接口可提走用户偿付资产

**严重程度：High**  
**处置状态：风险已接受（预期业务/权限模型）**  
**类别：资产安全 / 中心化风险**  
**位置：**

- `WrappedRtUSQ.rescueToken()`：`contracts/WrtUSQ.sol:21-35`
- `rtUSQVault.refundToken()`：`contracts/rtUSQVault.sol:103-115`

`WrappedRtUSQ.rescueToken()` 未禁止提取 `asset()`。owner 可以传入 rtUSQ 地址，把 ERC4626 中支撑全部 wrtUSQ 份额的底层资
产转走。转走后 `totalAssets()` 接近 0，普通用户 redeem/withdraw 将无法取得原本的底层资产。

Vault 的 `refundToken()` 同样允许 assetManager 提走 `tokenUsd`。虽然投资资金本来就直接交给 assetManager，但一旦运营方为
已登记的 `userAsset` 债务向 Vault 注入提现流动性，assetManager 仍可立即将其全部提走。

**影响：** 特权账户或其攻击者可造成全部 wrapper 用户损失，或使 Vault 提现债权无法兑付。

**建议：**

1. `WrappedRtUSQ.rescueToken()` 必须拒绝 `token == asset()`；如需处理多余底层资产，应只允许提取
   `balanceOf(this) - requiredAssets`，并明确定义 requiredAssets。
2. Vault 应禁止 `refundToken(tokenUsd, ...)`，或至少锁定覆盖 `sum(userAsset)` 的准备金。
3. owner/assetManager 使用多签与 Timelock；特权操作发出完整事件并设置链上监控。

### [M-01] Vault 的 maxSupply 可被单笔投资任意越过

**严重程度：Medium**  
**处置状态：风险已接受（预期业务逻辑）**  
**类别：业务逻辑**  
**位置：** `contracts/rtUSQVault.sol:66-76`

当前检查仅验证投资前的 `totalSubscribed >= maxSupply`。当 `totalSubscribed` 尚未达到上限时，任意大的 `_amount` 都会通
过。例如总认购量为 999,999 rtUSQ、上限为 1,000,000 时，用户仍可一次投资 10,000,000。

**影响：** 供应风险限制失效，可能显著超过资产管理和兑付能力。

**建议：** 使用：

```solidity
if (_amount == 0 || _amount > maxSupply - totalSubscribed) revert NotInvestable();
```

并明确 maxSupply 是累计认购上限还是当前流通供应上限。如果是当前供应上限，还需在 redeem/rebase 时同步定义其变化规则。

### [M-02] owner 可在已有债务时替换结算资产

**严重程度：Medium**  
**处置状态：风险已接受（预期业务/权限模型）**  
**类别：资产一致性 / 权限风险**  
**位置：** `contracts/rtUSQVault.sol:133-137`

`setUsdToken()` 可随时把 `tokenUsd` 改为任意地址，没有零地址、合约代码、decimals 或已有债务检查。当前版本已补充更新事
件，但 `userAsset` 仍只记录数值，不记录债务对应的资产。

若用户以资产 A 投资并形成 A 计价的提现债权，owner 随后把 `tokenUsd` 改成资产 B，则 `withdraw()` 会按相同原始数值支付 B。
不同价格或 decimals 会导致用户少收、多收，恶意配置甚至可改为无价值 token 或 EOA 使提现永久回退。

**建议：**

- 最安全方案是把结算资产设为 immutable。
- 如业务必须迁移资产，应采用独立迁移流程：暂停业务、清偿旧债务、验证 decimals/价格、设置新资产，并通过 Timelock 执行。
- 至少增加零地址、`code.length`、decimals 检查和 `UsdTokenUpdated` 事件。

### [M-03] Vault 按请求金额铸币，未验证实际收到的底层资产

**严重程度：Medium**  
**处置状态：风险已接受（结算币兼容范围由业务保证）**  
**类别：偿付能力 / Token 兼容性**  
**位置：** `contracts/rtUSQVault.sol:73-75`

Vault 将 `_amount` 直接转到 assetManager，并按 `_amount` 铸造 rtUSQ。若 `tokenUsd` 是 fee-on-transfer、rebase、黑名单或
其他非标准 token，assetManager 实际收到的金额可能小于 `_amount`，但用户仍取得全额 rtUSQ。

因为 `setUsdToken()` 可替换为任意 token，这不是纯理论兼容性问题。

**影响：** rtUSQ 可能在发行时即出现抵押不足。

**建议：**

- 将结算币限制为经过审核的 immutable 标准 ERC20；或
- 先转入 Vault，通过转账前后余额差计算 `received`，再把 `received` 转给 assetManager 并按 `received` 铸币；
- 明确拒绝 fee-on-transfer 和 rebasing 结算资产。

### [M-04] rebase 后的零份额取整会破坏 ERC20/份额记账一致性

**严重程度：Medium**  
**处置状态：已修复（2026-08-14）**  
**类别：舍入 / 会计一致性**  
**位置：**

- `getSharesByRt()` / `getRShares()`：`contracts/rtUSQ.sol:121-139`
- share transfer：`contracts/rtUSQ.sol:186-200`
- `_transfer()`：`contracts/rtUSQ.sol:203-209`
- `_mint()` / `_burn()`：`contracts/rtUSQ.sol:239-264`

正向 rebase 后，1 share 可能对应多个最小单位的 rtUSQ。小额 token 数量通过 `amount * totalShares / totalSupply` 向下取整
后可能得到 0 shares，但代码仍继续：

- transfer 返回 true 并发出非零 Transfer 事件，但双方 shares 均未变化；
- mint 增加 `_totalSupply`，但接收者没有获得 shares；
- burn 减少 `_totalSupply`，但账户 shares 没有减少。

这会让依赖 ERC20 返回值或 Transfer 日志的集成产生错误记账，并使供应量与份额变化不一致。正常 18 decimals 和当前较低
rebase rate 会限制单次可利用金额，但问题会随累计换算率增大，并可被合约循环调用放大。仓库中的 `rtBTC` 已在
transfer/mint/burn 和 share transfer 路径加入 `AMOUNT_TOO_SMALL` 检查。

**建议：** 将 `rtBTC` 的以下保护完整移植到 rtUSQ：

```solidity
require(amount == 0 || sharesAmount > 0, "AMOUNT_TOO_SMALL");
```

反向换算同样应保证非零 shares 不会转换成 0 token。建议使用 OpenZeppelin `Math.mulDiv` 明确处理乘法精度与舍入方向，并补充
正负 rebase 后的 deterministic fuzz/invariant 测试。

**修复说明：** 所有 token→shares 与 shares→token 的状态变更路径均增加 `AMOUNT_TOO_SMALL` 检查；非零输入若舍入为零将回
退，零金额 ERC20 操作仍保持兼容。

### [L-01] 首次铸币前部分标准 ERC20 查询会除以零

**严重程度：Low**  
**处置状态：已修复（2026-08-14）**  
**类别：可用性 / 标准兼容性**  
**位置：** `contracts/rtUSQ.sol:105-139`

部署后、首次 mint 前，`_totalSupply == 0` 且 `_totalShares == 0`。此时 `balanceOf()` 经 `getRShares()` 除以
`_totalShares`，`getSharesByRt()` 则除以 `totalSupply()`，都会回退。

**影响：** 区块浏览器、钱包、DEX、ERC4626 `totalAssets()` 及其他集成在首次发行前可能无法查询或初始化。

**建议：** 采用 `rtBTC` 的零状态处理：零供应/零份额时 `balanceOf` 和 `getRShares` 返回 0，首次换算时
`getSharesByRt(amount)` 返回 amount。

**修复说明：** 已加入上述零状态分支，并增加首次 mint 前的查询回归测试。

### [L-02] totalSubscribed 不随赎回变化，可能永久耗尽认购额度

**严重程度：Low**  
**处置状态：风险已接受（totalSubscribed 定义为业务累计值）**  
**类别：业务逻辑 / 可用性**  
**位置：**

- 增加：`contracts/rtUSQVault.sol:74`
- redeem：`contracts/rtUSQVault.sol:78-85`

`totalSubscribed` 只在 invest 时增加，在 redeem 时不减少。若 maxSupply 的业务含义是“当前已发行规模”，用户全部赎回后仍可
能无法再次投资。admin 虽可通过 `setMaxSupply()` 人工重写该值，但这使核心供应记账依赖链下操作。

**建议：** 明确变量语义。当前供应上限应基于 `rtUSQ.totalSupply()` 或在 redeem 时减少；累计销售上限则应改名为
`cumulativeSubscribed` 并写入文档。

### [L-03] rebase 控制参数缺少安全边界

**严重程度：Low**  
**处置状态：风险已接受（预期治理模型）**  
**类别：配置安全 / 权限风险**  
**位置：**

- `rtUSQ.setMonetaryPolicy()`：`contracts/rtUSQ.sol:66-69`
- `rtUSQ.rebase()`：`contracts/rtUSQ.sol:79-93`
- `setMaxRebaseRate()` / `setTimeInterval()`：`contracts/rtUSQRebase.sol:66-74`

rtUSQ owner 不受 Rebase 合约的时间和比例限制，可直接执行任意正负 rebase。Rebase owner 还可把 `maxRebaseRate` 设置为任意
值，把 `timeInterval` 设置为 0。`setMonetaryPolicy` 允许零地址且没有两步切换流程。

这主要是中心化/配置风险，但错误操作会造成供应剧烈变化、换算异常或协议停摆。

**建议：**

- 取消 rtUSQ owner 对 `rebase()` 的旁路权限，只允许经过验证的 monetaryPolicy；
- 为 rate 和 interval 设置协议级上下界；
- 使用两步角色迁移、Timelock 和多签；
- 为所有参数更新添加旧值/新值事件。

### [I-01] Vault 采用完全托管式偿付模型，链上不验证准备金

**严重程度：Informational**  
**处置状态：风险已接受（预期托管模型）**  
**类别：架构 / 中心化**

所有投资资产直接进入 assetManager，而 redeem 只生成 `userAsset` 债权。Vault 不检查 assetManager 储备，也不会自动取回资
金。withdraw 是否成功完全取决于运营方事先向 Vault 注入足够 tokenUsd。

**建议：** 在产品文档中明确这是托管式而非链上超额/全额抵押模型；提供储备证明、债务总额统计、提款队列和链上偿付率监控。若
目标是 trust-minimized vault，应让资金保留在受策略约束的合约中。

### [I-02] 无效依赖、事件和接口定义降低可维护性

**严重程度：Informational**  
**处置状态：已修复（2026-08-14）**  
**类别：代码质量**

原审计版本存在以下维护性问题：无效 Uniswap/TransferHelper 导入、接口 mutability 不完整、关键配置缺少事件，以及未使用的内
部份额函数。当前版本已完成对应清理。项目仍同时使用不同来源的 Ownable 与 Solidity 版本，该差异因现有兼容性暂时保留。

**建议：** 删除无效导入和死代码，统一 OpenZeppelin/编译器版本，补全接口 mutability 与配置事件，并对生产构建锁定依赖版
本。

**修复说明：** 已删除 Rebase 的无效 swap 依赖和 rtUSQ 未使用的内部份额函数，接口 `decimals()` 已标记为 `view`，并为结算
资产和 rebase 时间间隔更新补充事件。编译器版本差异因现有合约兼容性暂时保留，不影响本项运行时安全修复。

## 5. 测试与验证结果

以下测试在同步来源仓库 `cic-contracts` 的 Hardhat 环境中执行；当前独立 `rtUSQ` 仓库未包含 Hardhat 配置和测试框架。

执行命令：

```text
bun run compile
bunx hardhat test test/rtUSQ.ts test/WrtUSQ.ts test/UniV3WrapperCurveRouter.ts test/rtUSQWithdrawHelper.ts
```

结果：编译通过，相关测试 39 个全部通过。

现有测试覆盖了 ERC4626 deposit/mint/withdraw/redeem、Router 到 Vault 的投资流程和 WithdrawHelper，但缺少：

- `totalSupply`、`totalShares`、账户 shares 与余额之间的 invariant fuzz；
- owner/admin/assetManager 全权限矩阵及 Timelock 场景。

已修复项的专项回归测试包括：

- 首次 mint 前 `balanceOf`、`getSharesByRt`、`getRShares` 的零状态行为；
- 正向 rebase 后 transfer、burn、mint 的零份额拒绝；
- 负向 rebase 后 share transfer 的零 token 拒绝；
- 零金额 ERC20 操作兼容性；
- `UpdateUsdToken` 与 `UpdateTimeInterval` 配置事件。

## 6. 后续建议

当前没有项目方要求继续修复的技术项。建议后续：

1. 对已接受的特权和托管风险保留面向用户的明确披露。
2. owner、admin、assetManager 使用多签、角色隔离和链上监控。
3. 为 share/supply 换算增加长期 invariant fuzz，防止后续修改重新引入舍入问题。
4. 任何涉及资产流、rebase 算法或权限模型的后续变更应重新审计。

## 7. 结论与限制

本次审计基于当前本地工作区快照；工作区包含尚未提交的文件移动和功能修改，因此后续任何代码变化都可能使结论失效。本报告不是
形式化验证，也未覆盖部署地址的实际角色、代理、链上储备或外部协议安全。

M-04、L-01、I-02 已修复并通过回归测试。其余七项已由项目方确认为正常业务范围并接受相关风险，因此本轮复审不存在未处置的技
术发现。

rtUSQ 仍属于带受信任 owner/admin/assetManager 的托管式系统，不应被描述为无需信任或完全链上偿付的资产协议。生产部署结论仍
依赖这些角色的实际多签、权限配置、运营流程和链上储备情况，而这些内容不在本次代码审计范围内。
