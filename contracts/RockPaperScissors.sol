pragma solidity 0.5.7;
pragma experimental ABIEncoderV2;

import '../node_modules/openzeppelin-solidity/contracts/ownership/Ownable.sol';
import '../node_modules/openzeppelin-solidity/contracts/math/SafeMath.sol';

contract RockPaperScissors is Ownable {
    using SafeMath for uint;

    event LogSessionInitialized(address indexed sender, address indexed rivalAddress,
        uint stake, bytes32 indexed sessionHash);
    event LogSessionAccepted(address indexed sender, bytes32 indexed sessionHash, uint stake);
    event LogSessionCanceled(address indexed sender, bytes32 indexed sessionHash);
    event LogSessionFinalized(address indexed sender, bytes32 indexed sessionHash, int result);
    event LogSessionMoveMade(address indexed sender, bytes32 indexed sessionHash, bytes32 moveHash);
    event LogSessionMoveRevealed(address indexed sender, bytes32 indexed sessionHash,
        bytes32 secret, PlayerMove move);

    event LogFundsWithdrawn(address indexed sender, uint amount);
    event LogFundsDeposited(address indexed sender, uint amount);

    event LogSessionExpirationPeriod(address indexed sender, uint sessionExpirationPeriod);

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

    uint public sessionExpirationPeriod; // in seconds
    mapping (bytes32 => GameSession) public gameSessions; // sessionHash => gameSession
    mapping (address => uint) public balances; // playerAddress => balance

    constructor(uint _sessionExpirationPeriod) public {
        sessionExpirationPeriod = _sessionExpirationPeriod;

        emit LogSessionExpirationPeriod(msg.sender, _sessionExpirationPeriod);
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
        require(challengedAddress != address(0),
            "challengedAddress parameter cannot be equal to 0");
        require(challengedAddress != msg.sender,
            "challengedAddress cannot be equal to initAddress");
        require(stake <= balances[msg.sender],
            "stake parameter cannot be greater than the account balance");
        require((stake << 1) >= stake, "Total stake overflowed");
        require(moveHash != bytes32(0), "moveHash parameter cannot be equal to 0");

        sessionHash = moveHash;
        GameSession storage session = gameSessions[sessionHash];

        require(session.expirationTime == 0, "Session cannot be reinitialized");

        balances[msg.sender] = balances[msg.sender].sub(stake);
        session.stake = stake;
        session.expirationTime = now.add(sessionExpirationPeriod);

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

        require(session.challengedPlayer.account == msg.sender,
            "Session can be accepted only by the challenged player");
        require(session.stake <= balances[msg.sender],
            "challenged player balance is too low");
        require(session.challengedPlayerMoveHash == bytes32(0),
            "Session cannot be accepted more than once");

        uint stake = session.stake;

        balances[msg.sender] = balances[msg.sender].sub(stake);
        session.expirationTime = now.add(sessionExpirationPeriod);

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

            balances[initAddress] = balances[initAddress].add(stake << 1);
        } else if (session.initPlayer.lastMove == PlayerMove.NO_MOVE &&
            session.challengedPlayer.lastMove != PlayerMove.NO_MOVE) {

            balances[challengedAddress] = balances[challengedAddress].add(stake << 1);
        } else { // Game Session state is either Initialized or Accepted.
            balances[initAddress] = balances[initAddress].add(stake);

            if (session.challengedPlayerMoveHash != bytes32(0)) {
                // Accepted state: stake commited by the challenged player.
                balances[challengedAddress] = balances[challengedAddress].add(stake);
            }
        }

        delete gameSessions[sessionHash];

        emit LogSessionCanceled(msg.sender, sessionHash);

        return true;
    }

    function revealSessionMove(bytes32 sessionHash, bytes32 secret, PlayerMove move) public
    returns (bool success) {
        GameSession storage session = gameSessions[sessionHash];

        require(msg.sender == session.initPlayer.account ||
                msg.sender == session.challengedPlayer.account,
                "Session moves can only be revealed by the session participants");
        require((session.challengedPlayerMoveHash != bytes32(0)),
                "Cannot reveal moves at this session state");

        if (msg.sender == session.initPlayer.account) {
            bytes32 moveHash = getMoveHash(secret, move);
            bytes32 initPlayerMoveHash = sessionHash;

            require(session.initPlayer.lastMove == PlayerMove.NO_MOVE,
                "Cannot reveal the move again");
            require(initPlayerMoveHash == moveHash, "Move hash does not match");

            emit LogSessionMoveRevealed(msg.sender, sessionHash, secret, move);

            session.initPlayer.lastMove = move;
        } else if (msg.sender == session.challengedPlayer.account) {
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
                balances[session.initPlayer.account] =
                    balances[session.initPlayer.account].add(stake);
            }

            if (result <= 0) {
                balances[session.challengedPlayer.account] =
                    balances[session.challengedPlayer.account].add(stake);
            }

            delete gameSessions[sessionHash];

            emit LogSessionFinalized(msg.sender, sessionHash, result);
        } else {
            session.expirationTime = now.add(sessionExpirationPeriod);
        }

        return true;
    }

    function withdrawFunds(uint amount) public returns (bool success) {
        uint balance = balances[msg.sender];

        require(balance >= amount, "Balance is too low");

        balances[msg.sender] = balance.sub(amount);

        emit LogFundsWithdrawn(msg.sender, amount);

        msg.sender.transfer(amount);

        return true;
    }

    function depositFunds() public payable returns (bool success) {
        balances[msg.sender] = balances[msg.sender].add(msg.value);

        emit LogFundsDeposited(msg.sender, msg.value);

        return true;
    }

    function changeSessionExpirationPeriod(uint newSessionExpirationPeriod) public onlyOwner
    returns (bool success) {
        sessionExpirationPeriod = newSessionExpirationPeriod;

        emit LogSessionExpirationPeriod(msg.sender, newSessionExpirationPeriod);

        return true;
    }

}