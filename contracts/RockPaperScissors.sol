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
    event LogSessionMoveHashed(address indexed sender, bytes32 indexed sessionHash, bytes32 moveHash);
    event LogSessionMoveMade(address indexed sender, bytes32 indexed sessionHash, PlayerMove move);
    event LogSessionMoveRevealed(address indexed sender, bytes32 indexed sessionHash,
        bytes32 secret, PlayerMove move);

    event LogContractCreated(address indexed sender);

    enum PlayerMove {
        NO_MOVE,
        ROCK,
        PAPER,
        SCISSORS
    }

    struct GameSession {
        address initPlayer;
        address challengedPlayer;
        PlayerMove challengedPlayerMove;
        uint stake;
        uint expirationTime;
    }

    RockPaperScissorsHubInterface RPSHub;
    mapping (bytes32 => GameSession) public gameSessions; // sessionHash => gameSession

    constructor() public {
        RPSHub = RockPaperScissorsHubInterface(msg.sender);

        emit LogContractCreated(msg.sender);
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
    public returns (bool success) {
        require(challengedAddress != address(0),
            "challengedAddress parameter cannot be equal to 0");
        require(challengedAddress != msg.sender,
            "challengedAddress cannot be equal to initAddress");
        require((stake << 1) >= stake, "Total stake overflowed");
        require(moveHash != bytes32(0), "moveHash parameter cannot be equal to 0");

        GameSession storage session = gameSessions[moveHash];

        require(session.expirationTime == 0, "Session cannot be reinitialized");

        RPSHub.betStake(msg.sender, stake);

        session.stake = stake;
        session.expirationTime = now.add(RPSHub.sessionExpirationPeriod());

        session.initPlayer = msg.sender;
        session.challengedPlayer = challengedAddress;

        emit LogSessionInitialized(msg.sender, challengedAddress, stake, moveHash);
        emit LogSessionMoveHashed(msg.sender, moveHash, moveHash);

        return true;
    }

    function acceptSession(bytes32 sessionHash, PlayerMove move) public
    returns (bool success) {
        require(sessionHash != bytes32(0), "sessionHash parameter cannot be equal to 0");
        require((uint(move) > uint(PlayerMove.NO_MOVE)) &&
                (uint(move) <= uint(PlayerMove.SCISSORS)),
                "move parameter value is incorrect");

        GameSession storage session = gameSessions[sessionHash];

        require(session.challengedPlayer == msg.sender,
            "Session can be accepted only by the challenged player");
        require(session.challengedPlayerMove == PlayerMove.NO_MOVE,
            "Session cannot be accepted more than once");

        uint stake = session.stake;
        RPSHub.betStake(msg.sender, stake);

        session.expirationTime = now.add(RPSHub.sessionExpirationPeriod());
        session.challengedPlayerMove = move;

        emit LogSessionAccepted(msg.sender, sessionHash, stake);
        emit LogSessionMoveMade(msg.sender, sessionHash, move);

        return true;
    }

    function cancelSession(bytes32 sessionHash) public returns (bool success) {
        require(sessionHash != bytes32(0), "sessionHash parameter cannot be equal to 0");

        GameSession storage session = gameSessions[sessionHash];
        address initAddress = session.initPlayer;
        address challengedAddress = session.challengedPlayer;

        require(msg.sender == initAddress || msg.sender == challengedAddress,
                "Session can only be canceled by the session participants");
        require(now >= session.expirationTime, "Session has not expired yet");

        uint stake = session.stake;
        if (session.challengedPlayerMove != PlayerMove.NO_MOVE) {
            // Game Session is in the Accepted state.
            uint reward = (stake << 1);

            RPSHub.assignReward(challengedAddress, reward);
        } else {
            // Game Session is in the Initialized state.
            RPSHub.assignReward(initAddress, stake);
        }

        /* Clean up the session and leave the value of expiration time so the session hash
        cannot be reused. */
        session.initPlayer = address(0);
        session.challengedPlayer = address(0);
        session.challengedPlayerMove = PlayerMove.NO_MOVE;
        session.stake = 0;

        emit LogSessionCanceled(msg.sender, sessionHash);

        return true;
    }

    function revealSessionMove(bytes32 sessionHash, bytes32 secret, PlayerMove move) public
    returns (bool success) {
        GameSession storage session = gameSessions[sessionHash];
        address initAddress = session.initPlayer;
        address challengedAddress = session.challengedPlayer;

        require(msg.sender == initAddress,
                "Session move can only be revealed by the Initiator");
        require((session.challengedPlayerMove != PlayerMove.NO_MOVE),
                "Cannot reveal initiator move at this session state");

        require(sessionHash == getMoveHash(secret, move), "Move hash does not match");
        emit LogSessionMoveRevealed(msg.sender, sessionHash, secret, move);

        int result = lookupSessionResult(move, session.challengedPlayerMove);
        uint stake = session.stake;

        stake = (result != 0) ? (stake << 1) : stake;

        if (result >= 0) {
            RPSHub.assignReward(initAddress, stake);
        }

        if (result <= 0) {
            RPSHub.assignReward(challengedAddress, stake);
        }

        /* Clean up the session and leave the value of expiration time so the session hash
        cannot be reused. */
        session.initPlayer = address(0);
        session.challengedPlayer = address(0);
        session.challengedPlayerMove = PlayerMove.NO_MOVE;
        session.stake = 0;

        emit LogSessionFinalized(msg.sender, sessionHash, result);

        return true;
    }

}