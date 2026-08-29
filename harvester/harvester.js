require('dotenv').config();
const { ethers } = require('ethers');

// ── Config ─────────────────────────────────────────────────────────────────
const RPC_URL        = process.env.RPC_URL;
const PRIVATE_KEY    = process.env.PRIVATE_KEY;
const TREASURY       = process.env.STOCK_TREASURY;
const DISTRIBUTOR    = process.env.STOCK_DISTRIBUTOR;
const MIN_ETH        = ethers.parseEther(process.env.MIN_ETH_TO_BUY || '0.001');
const CHECK_INTERVAL = parseInt(process.env.CHECK_INTERVAL_MS) || 300000;

// ── Validate config ────────────────────────────────────────────────────────
if (!TREASURY || !DISTRIBUTOR) {
  console.log('ERROR: Contract addresses not set in .env');
  console.log('Set STOCK_TREASURY and STOCK_DISTRIBUTOR after mainnet deploy');
  process.exit(0);
}

// ── ABIs ───────────────────────────────────────────────────────────────────
const TREASURY_ABI = [
  'function buyStocks(uint256[] calldata minOuts) external',
  'function stocksLength() external view returns (uint256)',
  'function stockTokenAt(uint256 i) external view returns (address)',
  'function keeper(address) external view returns (bool)',
];

const DISTRIBUTOR_ABI = [
  'function canStart() external view returns (bool)',
  'function snapshotHolders(uint256 count) external',
  'function snapshotRemaining() external view returns (uint256)',
  'function startCycle() external',
  'function distributeBatch(uint256 count) external',
  'function cycleActive() external view returns (bool)',
  'function remaining() external view returns (uint256)',
  'function keeper(address) external view returns (bool)',
];

// ── Setup ──────────────────────────────────────────────────────────────────
const provider = new ethers.JsonRpcProvider(RPC_URL);
const wallet   = new ethers.Wallet(PRIVATE_KEY, provider);

const treasury    = new ethers.Contract(TREASURY, TREASURY_ABI, wallet);
const distributor = new ethers.Contract(DISTRIBUTOR, DISTRIBUTOR_ABI, wallet);

// ── Logging ────────────────────────────────────────────────────────────────
function log(msg) {
  console.log(`[${new Date().toISOString()}] ${msg}`);
}

// ── Buy stocks ─────────────────────────────────────────────────────────────
async function buyStocks() {
  try {
    const balance = await provider.getBalance(TREASURY);
    log(`Treasury ETH balance: ${ethers.formatEther(balance)} ETH`);

    if (balance < MIN_ETH) {
      log('Treasury balance too low — skipping buyStocks');
      return;
    }

    const stockCount = await treasury.stocksLength();
    log(`Stock count: ${stockCount}`);

    const minOuts = Array(Number(stockCount)).fill(0n);

    log('Calling buyStocks()...');
    const tx = await treasury.buyStocks(minOuts, {
      gasLimit: 500000n,
    });
    log(`buyStocks tx: ${tx.hash}`);
    await tx.wait();
    log('buyStocks confirmed!');

  } catch (err) {
    log(`buyStocks error: ${err.message}`);
  }
}

// ── Snapshot holders ───────────────────────────────────────────────────────
async function snapshotHolders() {
  try {
    const remaining = await distributor.snapshotRemaining();
    if (remaining === 0n) {
      log('Snapshot already complete');
      return;
    }

    log(`Snapshotting ${remaining} holders...`);
    const tx = await distributor.snapshotHolders(250n, {
      gasLimit: 3000000n,
    });
    log(`snapshotHolders tx: ${tx.hash}`);
    await tx.wait();
    log('Snapshot batch complete!');

  } catch (err) {
    log(`snapshotHolders error: ${err.message}`);
  }
}

// ── Start cycle ────────────────────────────────────────────────────────────
async function startCycle() {
  try {
    log('Starting distribution cycle...');
    const tx = await distributor.startCycle({
      gasLimit: 3000000n,
    });
    log(`startCycle tx: ${tx.hash}`);
    await tx.wait();
    log('Cycle started!');

  } catch (err) {
    log(`startCycle error: ${err.message}`);
  }
}

// ── Distribute batch ───────────────────────────────────────────────────────
async function distributeBatch() {
  try {
    const remaining = await distributor.remaining();
    if (remaining === 0n) {
      log('No remaining holders to distribute');
      return;
    }

    log(`Distributing to ${remaining} holders...`);
    const tx = await distributor.distributeBatch(25n, {
      gasLimit: 3000000n,
    });
    log(`distributeBatch tx: ${tx.hash}`);
    await tx.wait();
    log('Batch distributed!');

  } catch (err) {
    log(`distributeBatch error: ${err.message}`);
  }
}

// ── Main loop ──────────────────────────────────────────────────────────────
async function run() {
  log('🌊 StockStream Keeper starting...');
  log(`Wallet: ${wallet.address}`);
  log(`Treasury: ${TREASURY}`);
  log(`Distributor: ${DISTRIBUTOR}`);
  log(`Check interval: ${CHECK_INTERVAL / 1000}s`);

  while (true) {
    try {
      log('--- StockStream Keeper tick ---');

      // Step 1: Buy stocks with treasury ETH
      await buyStocks();

      // Step 2: Check cycle status
      const cycleActive = await distributor.cycleActive();

      if (cycleActive) {
        // Step 3a: Continue active cycle
        log('Cycle active — distributing batch...');
        await distributeBatch();

      } else {
        const canStart = await distributor.canStart();

        if (canStart) {
          // Step 3b: Snapshot then start new cycle
          log('Ready for new cycle!');
          await snapshotHolders();
          await startCycle();
          await distributeBatch();
        } else {
          log('Not ready for distribution yet — waiting...');
        }
      }

    } catch (err) {
      log(`Main loop error: ${err.message}`);
    }

    log(`Sleeping ${CHECK_INTERVAL / 1000}s...`);
    await new Promise(r => setTimeout(r, CHECK_INTERVAL));
  }
}

// ── Start ──────────────────────────────────────────────────────────────────
run().catch(err => {
  log(`Fatal error: ${err.message}`);
  process.exit(1);
});