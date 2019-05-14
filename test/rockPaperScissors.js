const assert = require('assert-plus');
const truffleAssert = require('truffle-assertions');
const truffleContract = require("truffle-contract");

require('events').EventEmitter.defaultMaxListeners = 60;

const addEvmFunctions = require("./utils/evmFunctions.js");

const Web3 = require('web3');
const web3 = new Web3();

const Ganache = require('ganache-cli');
web3.setProvider(Ganache.provider());

const RockPaperScissors = truffleContract(require(__dirname + "/../build/contracts/RockPaperScissors.json"));
RockPaperScissors.setProvider(web3.currentProvider);

describe("RockPaperScissors", function() {

    let rockPaperScissorsInstance;

    let ownerAddress;
    let aliceAddress;
    let bobAddress;

    const defaultSessionExpirationPeriod = 6*3600; // 6 hours.

    before("setup global variables", async () => {
        accounts = await web3.eth.getAccounts();
        ownerAddress = accounts[0];
        aliceAddress = accounts[1];
        bobAddress = accounts[2];

        networkId = await web3.eth.net.getId();
        RockPaperScissors.setNetwork(networkId);
    });

    beforeEach('setup contract for each test', async () => {
        rockPaperScissorsInstance = await RockPaperScissors.new(
            defaultSessionExpirationPeriod, {from: ownerAddress});
    });

    describe("admin operations", function() {

        it('should change the expiration period for each game session', async () => {
            const newSessionExpirationPeriod = 9*24*3600; // 9 days.
            const owner = await rockPaperScissorsInstance.owner();

            await rockPaperScissorsInstance.changeSessionExpirationPeriod(
                newSessionExpirationPeriod, {from: owner});

            const sessionExpirationPeriod = await
                rockPaperScissorsInstance.sessionExpirationPeriod();

            assert.strictEqual(sessionExpirationPeriod.toString(),
                newSessionExpirationPeriod.toString(),
                "Session expiration periods do not match");
        });

    });

    describe("withdrawal and deposit operations", function() {

        const { BN } = web3.utils;

        it('should do the proper accounting of deposited funds', async () => {
            const fundsValue = 1000;

            await rockPaperScissorsInstance.depositFunds(
                {from: aliceAddress, value: fundsValue});

            const aliceBalance = await
                rockPaperScissorsInstance.balances(aliceAddress);

            assert.strictEqual(aliceBalance.toString(), fundsValue.toString(),
                "Alice balance is not correct");
        });

        it('should do the proper accounting after multiple deposit operations', async () => {
            const firstFundsValue = 1000;
            const secondFundsValue = 2000;

            await rockPaperScissorsInstance.depositFunds(
                {from: bobAddress, value: firstFundsValue});

            let bobBalance = await
                rockPaperScissorsInstance.balances(bobAddress);

            assert.strictEqual(bobBalance.toString(), firstFundsValue.toString(),
                "Bob balance is not correct");

            await rockPaperScissorsInstance.depositFunds(
                    {from: bobAddress, value: secondFundsValue});

            bobBalance = await
                rockPaperScissorsInstance.balances(bobAddress);

            assert.strictEqual(bobBalance.toString(),
                (firstFundsValue + secondFundsValue).toString(),
                "Bob balance is not correct");
        });

        it('should do the proper accounting after deposit and withdrawal operation', async () => {
            const depositValue = 1000;
            const withdrawalValue = 700;

            await rockPaperScissorsInstance.depositFunds(
                {from: bobAddress, value: depositValue});

            let bobBalance = await
                rockPaperScissorsInstance.balances(bobAddress);

            assert.strictEqual(bobBalance.toString(), depositValue.toString(),
                "Bob balance is not correct");

            await rockPaperScissorsInstance.withdrawFunds(withdrawalValue,
                {from: bobAddress});

            bobBalance = await
                rockPaperScissorsInstance.balances(bobAddress);

            assert.strictEqual(bobBalance.toString(),
                (depositValue - withdrawalValue).toString(),
                "Bob balance is not correct");
        });

        it('should do the proper accounting after multiple withdrawal operations', async () => {
            const depositValue = 1000;
            const firstWithdrawalValue = 300;
            const secondWithdrawalValue = 700;

            await rockPaperScissorsInstance.depositFunds(
                {from: bobAddress, value: depositValue});

            let bobBalance = await
                rockPaperScissorsInstance.balances(bobAddress);

            assert.strictEqual(bobBalance.toString(), depositValue.toString(),
                "Bob balance is not correct");

            await rockPaperScissorsInstance.withdrawFunds(firstWithdrawalValue,
                {from: bobAddress});

            bobBalance = await
                rockPaperScissorsInstance.balances(bobAddress);

            assert.strictEqual(bobBalance.toString(),
                (depositValue - firstWithdrawalValue).toString(),
                "Bob balance is not correct");

            await rockPaperScissorsInstance.withdrawFunds(secondWithdrawalValue,
                {from: bobAddress});

            bobBalance = await
                rockPaperScissorsInstance.balances(bobAddress);

            assert.strictEqual(bobBalance.toString(),
                (depositValue - firstWithdrawalValue - secondWithdrawalValue).toString(),
                "Bob balance is not correct");
        });

        it('should fail to widthraw more funds than the balance permits', async () => {
            const depositValue = 1000;
            const withdrawalValue = 1001;

            await rockPaperScissorsInstance.depositFunds(
                {from: bobAddress, value: depositValue});

            let bobBalance = await
                rockPaperScissorsInstance.balances(bobAddress);

            assert.strictEqual(bobBalance.toString(), depositValue.toString(),
                "Bob balance is not correct");

            await truffleAssert.fails(
                rockPaperScissorsInstance.withdrawFunds(withdrawalValue,
                    {from: bobAddress}));
        });

        it('should change external account balance during withdrawal operation', async () => {
            const fundsValue = 499;
            const gasPrice = await web3.eth.getGasPrice();

            await rockPaperScissorsInstance.depositFunds({from: aliceAddress, value: fundsValue});

            const alicePreBalance = await web3.eth.getBalance(aliceAddress);

            const aliceTxObj = await rockPaperScissorsInstance.withdrawFunds(fundsValue,
                {from: aliceAddress, gasPrice: gasPrice});

            const aliceBalanceChange = new BN(fundsValue - aliceTxObj.receipt.gasUsed * gasPrice);
            const expectedAliceBalance = new BN(alicePreBalance).add(aliceBalanceChange);
            const aliceBalance = await web3.eth.getBalance(aliceAddress);

            assert.strictEqual(aliceTxObj.receipt.status, true, "Alice TX failed");
            assert.strictEqual(aliceBalance, expectedAliceBalance.toString(),
                                "Alice balance is not correct");
        });

    });

    describe("game session related operations", function() {

        const { soliditySha3 } = web3.utils;

        addEvmFunctions(web3);

        const bobInitialBalance = 1000;
        const aliceInitialBalance = 1000;

        let salt;
        let sessionHash;

        const PlayerMove = {
            NO_MOVE: 0,
            ROCK: 1,
            PAPER: 2,
            SCISSORS: 3
        };

        before("setup global variables for game session", async () => {
            salt = (await web3.eth.getBlock("latest")).hash;
            sessionHash = await rockPaperScissorsInstance.getSessionHash(
                aliceAddress, bobAddress, salt);
        });

        beforeEach('setup initial balance for Alice and Bob', async () => {
            await rockPaperScissorsInstance.depositFunds(
                {from: aliceAddress, value: aliceInitialBalance});

            await rockPaperScissorsInstance.depositFunds(
                {from: bobAddress, value: bobInitialBalance});
        });

        it('should initialize game session between Alice & Bob', async () => {
            const stake = 500;
            const secret = soliditySha3("password", await web3.eth.getBlock("latest"));
            const moveHash = await rockPaperScissorsInstance.getMoveHash(
                sessionHash, secret, PlayerMove.SCISSORS, {from: aliceAddress});

            await rockPaperScissorsInstance.initSession(bobAddress, stake, moveHash, salt,
                {from: aliceAddress});

            const gameSession = await
                rockPaperScissorsInstance.gameSessions(sessionHash);

            assert.strictEqual(gameSession.stake.toString(), stake.toString(),
                "Stake is not correct");
            assert.ok(gameSession.expirationTime > 0, "Expiration time is not set");

            assert.strictEqual(gameSession.initPlayer.account, aliceAddress,
                "Init address is not correct");
            assert.strictEqual(gameSession.initPlayer.moveHash, moveHash,
                "Init move hash is not correct");
            assert.strictEqual(gameSession.initPlayer.lastMove, PlayerMove.NO_MOVE.toString(),
                "Init move is not correct");

            assert.strictEqual(gameSession.challengedPlayer.account, bobAddress,
                "Challenged address is not correct");

            const aliceBalance = await
                rockPaperScissorsInstance.balances(aliceAddress);

            assert.strictEqual(aliceBalance.toString(),
                (aliceInitialBalance - stake).toString(),
                "Alice balance is not correct");
        });

        it('should not let reinitialize session by either Alice or Bob', async () => {
            const stake = 500;
            const secret = soliditySha3("password", await web3.eth.getBlock("latest"));
            const moveHash = await rockPaperScissorsInstance.getMoveHash(
                sessionHash, secret, PlayerMove.SCISSORS, {from: aliceAddress});

            await rockPaperScissorsInstance.initSession(bobAddress, stake, moveHash, salt,
                {from: aliceAddress});

            const initGameSession = await
                rockPaperScissorsInstance.gameSessions(sessionHash);

            await truffleAssert.fails(rockPaperScissorsInstance.initSession(
                bobAddress, stake, moveHash, salt, {from: aliceAddress}));

            await truffleAssert.fails(rockPaperScissorsInstance.initSession(
                bobAddress, stake, moveHash, salt, {from: bobAddress}));

            const gameSession = await
                rockPaperScissorsInstance.gameSessions(sessionHash);

            assert.deepStrictEqual(gameSession, initGameSession, "Sessions are different");
        });

        it('should not let Alice reveal the move before hash submission from Bob', async () => {
            const stake = 500;
            const secret = soliditySha3("password", await web3.eth.getBlock("latest"));
            const aliceMove = PlayerMove.SCISSORS;
            const moveHash = await rockPaperScissorsInstance.getMoveHash(
                sessionHash, secret, aliceMove, {from: aliceAddress});

            await rockPaperScissorsInstance.initSession(bobAddress, stake, moveHash, salt,
                {from: aliceAddress});

            const initGameSession = await
                rockPaperScissorsInstance.gameSessions(sessionHash);

            await truffleAssert.fails(rockPaperScissorsInstance.revealSessionMove(
                sessionHash, secret, aliceMove, {from: aliceAddress}));

            const gameSession = await
                rockPaperScissorsInstance.gameSessions(sessionHash);

            assert.deepStrictEqual(gameSession, initGameSession, "Sessions are different");
        });

        it('should not let cancel immediately after session initialization', async () => {
            const stake = 500;
            const secret = soliditySha3("password", await web3.eth.getBlock("latest"));
            const moveHash = await rockPaperScissorsInstance.getMoveHash(
                sessionHash, secret, PlayerMove.SCISSORS, {from: aliceAddress});

            await rockPaperScissorsInstance.initSession(bobAddress, stake, moveHash, salt,
                {from: aliceAddress});

            const initGameSession = await
                rockPaperScissorsInstance.gameSessions(sessionHash);

            await truffleAssert.fails(rockPaperScissorsInstance.cancelSession(
                sessionHash, stake, moveHash, {from: aliceAddress}));

            await truffleAssert.fails(rockPaperScissorsInstance.initSession(
                aliceAddress, stake, moveHash, salt, {from: bobAddress}));

            const gameSession = await
                rockPaperScissorsInstance.gameSessions(sessionHash);

            assert.deepStrictEqual(gameSession, initGameSession, "Sessions are different");
        });

        it('should let cancel the session after expiration time', async () => {
            const stake = 500;
            const secret = soliditySha3("password", await web3.eth.getBlock("latest"));
            const moveHash = await rockPaperScissorsInstance.getMoveHash(
                sessionHash, secret, PlayerMove.SCISSORS, {from: aliceAddress});

            const initGameSession = await
                rockPaperScissorsInstance.gameSessions(sessionHash);

            await rockPaperScissorsInstance.initSession(bobAddress, stake, moveHash, salt,
                {from: aliceAddress});
            await web3.evm.increaseTime(defaultSessionExpirationPeriod);
            await rockPaperScissorsInstance.cancelSession(sessionHash, {from: aliceAddress});

            const gameSession = await
                rockPaperScissorsInstance.gameSessions(sessionHash);

            assert.deepStrictEqual(gameSession, initGameSession, "Sessions are different");
        });

        it('should fail at init with incorrect parameters', async () => {
            const stake = aliceInitialBalance + 1;
            const secret = soliditySha3("password", await web3.eth.getBlock("latest"));
            const moveHash = await rockPaperScissorsInstance.getMoveHash(
                sessionHash, secret, PlayerMove.SCISSORS, {from: aliceAddress});

            await truffleAssert.fails(rockPaperScissorsInstance.initSession(
                    bobAddress, stake, moveHash, salt, {from: aliceAddress}));

            await truffleAssert.fails(rockPaperScissorsInstance.initSession(
                bobAddress, stake, moveHash, salt, {from: bobAddress}));
        });

        it('should establish game session between Alice & Bob', async () => {
            const stake = 500;
            const block = await web3.eth.getBlock("latest");

            const aliceSecret = soliditySha3("alice_password", block);
            const aliceMoveHash = await rockPaperScissorsInstance.getMoveHash(
                sessionHash, aliceSecret, PlayerMove.SCISSORS, {from: aliceAddress});

            const bobSecret = soliditySha3("bob_password", block);
            const bobMoveHash = await rockPaperScissorsInstance.getMoveHash(
                sessionHash, bobSecret, PlayerMove.PAPER, {from: bobAddress});

            await rockPaperScissorsInstance.initSession(bobAddress, stake, aliceMoveHash,
                salt, {from: aliceAddress});
            await rockPaperScissorsInstance.acceptSession(sessionHash, bobMoveHash,
                {from: bobAddress});

            const gameSession = await
                rockPaperScissorsInstance.gameSessions(sessionHash);

            assert.strictEqual(gameSession.stake.toString(), stake.toString(),
                "Stake is not correct");
            assert.ok(gameSession.expirationTime > 0, "Expiration time is not set");

            assert.strictEqual(gameSession.initPlayer.account, aliceAddress,
                "Init address is not correct");
            assert.strictEqual(gameSession.initPlayer.moveHash, aliceMoveHash,
                "Init move hash is not correct");
            assert.strictEqual(gameSession.initPlayer.lastMove, PlayerMove.NO_MOVE.toString(),
                "Init move is not correct");

            assert.strictEqual(gameSession.challengedPlayer.account, bobAddress,
                "Challenged address is not correct");
            assert.strictEqual(gameSession.challengedPlayer.moveHash, bobMoveHash,
                "Challenged move hash is not correct");
            assert.strictEqual(gameSession.challengedPlayer.lastMove, PlayerMove.NO_MOVE.toString(),
                "Challenged move is not correct");

            const aliceBalance = await
                rockPaperScissorsInstance.balances(aliceAddress);
            const bobBalance = await
                rockPaperScissorsInstance.balances(bobAddress);

            assert.strictEqual(aliceBalance.toString(),
                (aliceInitialBalance - stake).toString(),
                "Alice balance is not correct");
            assert.strictEqual(bobBalance.toString(),
                (bobInitialBalance - stake).toString(),
                "Bob balance is not correct");
        });

        it('should let Alice reveal her move', async () => {
            const stake = 500;
            const block = await web3.eth.getBlock("latest");

            const aliceMove = PlayerMove.SCISSORS;
            const aliceSecret = soliditySha3("alice_password", block);
            const aliceMoveHash = await rockPaperScissorsInstance.getMoveHash(
                sessionHash, aliceSecret, aliceMove, {from: aliceAddress});

            const bobSecret = soliditySha3("bob_password", block);
            const bobMoveHash = await rockPaperScissorsInstance.getMoveHash(
                sessionHash, bobSecret, PlayerMove.PAPER, {from: bobAddress});

            await rockPaperScissorsInstance.initSession(bobAddress, stake, aliceMoveHash,
                salt, {from: aliceAddress});
            await rockPaperScissorsInstance.acceptSession(sessionHash, bobMoveHash,
                {from: bobAddress});
            await rockPaperScissorsInstance.revealSessionMove(sessionHash, aliceSecret,
                aliceMove, {from: aliceAddress});

            const gameSession = await
                rockPaperScissorsInstance.gameSessions(sessionHash);

            assert.strictEqual(gameSession.stake.toString(), stake.toString(),
                "Stake is not correct");
            assert.ok(gameSession.expirationTime > 0, "Expiration time is not set");

            assert.strictEqual(gameSession.initPlayer.account, aliceAddress,
                "Init address is not correct");
            assert.strictEqual(gameSession.initPlayer.moveHash, aliceMoveHash,
                "Init move hash is not correct");
            assert.strictEqual(gameSession.initPlayer.lastMove, aliceMove.toString(),
                "Init move is not correct");

            assert.strictEqual(gameSession.challengedPlayer.account, bobAddress,
                "Challenged address is not correct");
            assert.strictEqual(gameSession.challengedPlayer.moveHash, bobMoveHash,
                "Challenged move hash is not correct");
            assert.strictEqual(gameSession.challengedPlayer.lastMove, PlayerMove.NO_MOVE.toString(),
                "Challenged move is not correct");

            const aliceBalance = await
                rockPaperScissorsInstance.balances(aliceAddress);
            const bobBalance = await
                rockPaperScissorsInstance.balances(bobAddress);

            assert.strictEqual(aliceBalance.toString(),
                (aliceInitialBalance - stake).toString(),
                "Alice balance is not correct");
            assert.strictEqual(bobBalance.toString(),
                (bobInitialBalance - stake).toString(),
                "Bob balance is not correct");
        });

        it('should let Alice win', async () => {
            const stake = 500;
            const block = await web3.eth.getBlock("latest");

            const aliceMove = PlayerMove.SCISSORS;
            const aliceSecret = soliditySha3("alice_password", block);
            const aliceMoveHash = await rockPaperScissorsInstance.getMoveHash(
                sessionHash, aliceSecret, aliceMove, {from: aliceAddress});

            const bobMove = PlayerMove.PAPER;
            const bobSecret = soliditySha3("bob_password", block);
            const bobMoveHash = await rockPaperScissorsInstance.getMoveHash(
                sessionHash, bobSecret, bobMove, {from: bobAddress});

            const initGameSession = await
                rockPaperScissorsInstance.gameSessions(sessionHash);

            await rockPaperScissorsInstance.initSession(bobAddress, stake, aliceMoveHash,
                salt, {from: aliceAddress});
            await rockPaperScissorsInstance.acceptSession(sessionHash, bobMoveHash,
                {from: bobAddress});
            await rockPaperScissorsInstance.revealSessionMove(sessionHash, aliceSecret,
                aliceMove, {from: aliceAddress});
            await rockPaperScissorsInstance.revealSessionMove(sessionHash, bobSecret,
                bobMove, {from: bobAddress});

            const gameSession = await
                rockPaperScissorsInstance.gameSessions(sessionHash);

            assert.deepStrictEqual(gameSession, initGameSession, "Sessions are different");

            const aliceBalance = await
                rockPaperScissorsInstance.balances(aliceAddress);
            const bobBalance = await
                rockPaperScissorsInstance.balances(bobAddress);

            assert.strictEqual(aliceBalance.toString(),
                (aliceInitialBalance + stake).toString(),
                "Alice balance is not correct");
            assert.strictEqual(bobBalance.toString(),
                (bobInitialBalance - stake).toString(),
                "Bob balance is not correct");
        });

    });

});