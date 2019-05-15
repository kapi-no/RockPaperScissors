pragma solidity 0.5.7;
pragma experimental ABIEncoderV2;

import '../node_modules/openzeppelin-solidity/contracts/math/SafeMath.sol';

import './RockPaperScissorsHub.sol';

contract RockPaperScissors {
    using SafeMath for uint;

    event LogSessionInitialized(address indexed sender, address indexed rivalAddress,
        uint stake, bytes32 indexed sessionHash);
    event LogSessionAccepted(address indexed sender, bytes32 indexed sessionHash, uint stake);
    event LogSessionCanceled(address indexed sender, bytes32 indexed sessionHash);
    event LogSessionFinalized(address indexed sender, bytes32 indexed sessionHash, int result);
    event LogSessionMoveMade(address indexed sender, bytes32 indexed sessionHash, bytes32 moveHash);
    event LogSessionMoveRevealed(address indexed sender, bytes32 indexed sessionHash,
        bytes32 secret, PlayerMove move);

    event LogContractCreated(address indexed sender, address indexed hubContract);

    enum PlayerMove {
        NO_MOVE,
        ROCK,
        PAPER,
        SCISSORS
    }

    struct Player {
        address account;
        PlayerMove lastMove;
    }

    struct GameSession {
        Player initPlayer;
        Player challengedPlayer;
        bytes32 challengedPlayerMoveHash;
        uint stake;
        uint expirationTime;
    }

    RockPaperScissorsHub RPSHub;
    mapping (bytes32 => GameSession) public gameSessions; // sessionHash => gameSession

    constructor(address _RPSHub) public {
        require(_RPSHub != address(0),
            "_RPSHub parameter cannot be equal to 0");
        RPSHub = RockPaperScissorsHub(_RPSHub);

        emit LogContractCreated(msg.sender, _RPSHub);
    }

    function lookupSessionResult(PlayerMove firstMove, PlayerMove secondMove)
    public pure returns (int result) {
        result = (3 + int(firstMove) - int(secondMove)) % 3;
        result = (result != 2) ? result : -1;
    }

    function getMoveHash(bytes32 secret, PlayerMove move) public view
    returns (bytes32 accessHash) {
        require(secret != bytes32(0), "secret parameter cannot be equal to 0");
        require((uint(move) > uint(PlayerMove.NO_MOVE)) &&
                (uint(move) <= uint(PlayerMove.SCISSORS)),
                "move parameter value is incorrect");

        accessHash = keccak256(abi.encodePacked(msg.sender, address(this), secret, move));
    }

    function initSession(address challengedAddress, uint stake, bytes32 moveHash)
    public returns (bytes32 sessionHash) {
        uint balance = RPSHub.balances(msg.sender);

        require(challengedAddress != address(0),
            "challengedAddress parameter cannot be equal to 0");
        require(challengedAddress != msg.sender,
            "challengedAddress cannot be equal to initAddress");
        require(stake <= balance,
            "stake parameter cannot be greater than the account balance");
        require((stake << 1) >= stake, "Total stake overflowed");
        require(moveHash != bytes32(0), "moveHash parameter cannot be equal to 0");

        sessionHash = moveHash;
        GameSession storage session = gameSessions[sessionHash];

        require(session.expirationTime == 0, "Session cannot be reinitialized");

        balance = balance.sub(stake);
        RPSHub.updateBalance(msg.sender, balance);

        session.stake = stake;
        session.expirationTime = now.add(RPSHub.sessionExpirationPeriod());

        session.initPlayer.account = msg.sender;

        session.challengedPlayer.account = challengedAddress;

        emit LogSessionInitialized(msg.sender, challengedAddress, stake, sessionHash);
        emit LogSessionMoveMade(msg.sender, sessionHash, moveHash);
    }

    function acceptSession(bytes32 sessionHash, bytes32 moveHash) public
    returns (bool success) {
        require(sessionHash != bytes32(0), "sessionHash parameter cannot be equal to 0");
        require(moveHash != bytes32(0), "moveHash parameter cannot be equal to 0");

        GameSession storage session = gameSessions[sessionHash];
        uint balance = RPSHub.balances(msg.sender);

        require(session.challengedPlayer.account == msg.sender,
            "Session can be accepted only by the challenged player");
        require(session.stake <= balance,
            "challenged player balance is too low");
        require(session.challengedPlayerMoveHash == bytes32(0),
            "Session cannot be accepted more than once");

        uint stake = session.stake;
        balance = balance.sub(stake);
        RPSHub.updateBalance(msg.sender, balance);

        session.expirationTime = now.add(RPSHub.sessionExpirationPeriod());
        session.challengedPlayerMoveHash = moveHash;

        emit LogSessionAccepted(msg.sender, sessionHash, stake);
        emit LogSessionMoveMade(msg.sender, sessionHash, moveHash);

        return true;
    }

    function cancelSession(bytes32 sessionHash) public returns (bool success) {
        require(sessionHash != bytes32(0), "sessionHash parameter cannot be equal to 0");

        GameSession storage session = gameSessions[sessionHash];
        address initAddress = session.initPlayer.account;
        address challengedAddress = session.challengedPlayer.account;

        require(msg.sender == initAddress || msg.sender == challengedAddress,
                "Session can only be canceled by the session participants");
        require(now >= session.expirationTime, "Session has not expired yet");

        uint stake = session.stake;
        if (session.initPlayer.lastMove != PlayerMove.NO_MOVE &&
            session.challengedPlayer.lastMove == PlayerMove.NO_MOVE) {
            uint initBalance = RPSHub.balances(initAddress);
            initBalance = initBalance.add(stake << 1);

            RPSHub.updateBalance(initAddress, initBalance);
        } else if (session.initPlayer.lastMove == PlayerMove.NO_MOVE &&
            session.challengedPlayer.lastMove != PlayerMove.NO_MOVE) {
            uint challengedBalance = RPSHub.balances(challengedAddress);
            challengedBalance = challengedBalance.add(stake << 1);

            RPSHub.updateBalance(challengedAddress, challengedBalance);
        } else { // Game Session state is either Initialized or Accepted.
            uint initBalance = RPSHub.balances(initAddress);
            initBalance = initBalance.add(stake);

            RPSHub.updateBalance(initAddress, initBalance);

            if (session.challengedPlayerMoveHash != bytes32(0)) {
                // Accepted state: stake commited by the challenged player.
                uint challengedBalance = RPSHub.balances(challengedAddress);
                challengedBalance = challengedBalance.add(stake);

                RPSHub.updateBalance(challengedAddress, challengedBalance);
            }
        }

        delete gameSessions[sessionHash];

        emit LogSessionCanceled(msg.sender, sessionHash);

        return true;
    }

    function revealSessionMove(bytes32 sessionHash, bytes32 secret, PlayerMove move) public
    returns (bool success) {
        GameSession storage session = gameSessions[sessionHash];
        address initAddress = session.initPlayer.account;
        address challengedAddress = session.challengedPlayer.account;

        require(msg.sender == initAddress || msg.sender == challengedAddress,
                "Session moves can only be revealed by the session participants");
        require((session.challengedPlayerMoveHash != bytes32(0)),
                "Cannot reveal moves at this session state");

        if (msg.sender == initAddress) {
            bytes32 moveHash = getMoveHash(secret, move);
            bytes32 initPlayerMoveHash = sessionHash;

            require(session.initPlayer.lastMove == PlayerMove.NO_MOVE,
                "Cannot reveal the move again");
            require(initPlayerMoveHash == moveHash, "Move hash does not match");

            emit LogSessionMoveRevealed(msg.sender, sessionHash, secret, move);

            session.initPlayer.lastMove = move;
        } else if (msg.sender == challengedAddress) {
            bytes32 moveHash = getMoveHash(secret, move);

            require(session.challengedPlayer.lastMove == PlayerMove.NO_MOVE,
                "Cannot reveal the move again");
            require(session.challengedPlayerMoveHash == moveHash, "Move hash does not match");

            emit LogSessionMoveRevealed(msg.sender, sessionHash, secret, move);

            session.challengedPlayer.lastMove = move;
        } else {
            revert("Unauthorized access to the request session");
        }

        if ((session.initPlayer.lastMove != PlayerMove.NO_MOVE) &&
            (session.challengedPlayer.lastMove != PlayerMove.NO_MOVE)) {
            int result = lookupSessionResult(session.initPlayer.lastMove,
                session.challengedPlayer.lastMove);
            uint stake = session.stake;

            stake = (result != 0) ? (stake << 1) : stake;

            if (result >= 0) {
                uint balance = RPSHub.balances(initAddress);
                balance = balance.add(stake);

                RPSHub.updateBalance(initAddress, balance);
            }

            if (result <= 0) {
                uint balance = RPSHub.balances(challengedAddress);
                balance = balance.add(stake);

                RPSHub.updateBalance(challengedAddress, balance);
            }

            delete gameSessions[sessionHash];

            emit LogSessionFinalized(msg.sender, sessionHash, result);
        } else {
            session.expirationTime = now.add(RPSHub.sessionExpirationPeriod());
        }

        return true;
    }

}