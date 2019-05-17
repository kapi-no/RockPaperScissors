pragma solidity 0.5.7;
pragma experimental ABIEncoderV2;

import '../node_modules/openzeppelin-solidity/contracts/ownership/Ownable.sol';
import '../node_modules/openzeppelin-solidity/contracts/math/SafeMath.sol';

contract RockPaperScissorsHub is Ownable {
    using SafeMath for uint;

    event LogFundsWithdrawn(address indexed sender, uint amount);
    event LogFundsDeposited(address indexed sender, uint amount);

    event LogBalanceUpdated(address indexed sender, address indexed account, uint balance);

    event LogSessionExpirationPeriod(address indexed sender, uint sessionExpirationPeriod);
    event LogRPSContractRegistered(address indexed sender, address indexed RPSContract);

    mapping(bytes32 => bool) private RPSContracts;

    uint public sessionExpirationPeriod; // in seconds
    mapping (address => uint) public balances; // playerAddress => balance

    modifier onlyRPSContracts() {
        require(RPSContracts[keccak256(abi.encodePacked(msg.sender))],
            "Contract is not registered");
        _;
    }

    constructor(uint _sessionExpirationPeriod) public {
        sessionExpirationPeriod = _sessionExpirationPeriod;

        emit LogSessionExpirationPeriod(msg.sender, _sessionExpirationPeriod);
    }

    function updateBalance(address playerAddress, uint newBalance) public onlyRPSContracts
    returns (bool success) {
        balances[playerAddress] = newBalance;

        emit LogBalanceUpdated(msg.sender, playerAddress, newBalance);
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

    function registerContract(address RPSContract) public onlyOwner
    returns (bool success) {
        require(RPSContract != address(0), "Address cannot be equal to zero");

        RPSContracts[keccak256(abi.encodePacked(RPSContract))] = true;
        emit LogRPSContractRegistered(msg.sender, RPSContract);

        return true;
    }

    function changeSessionExpirationPeriod(uint newSessionExpirationPeriod) public onlyOwner
    returns (bool success) {
        sessionExpirationPeriod = newSessionExpirationPeriod;

        emit LogSessionExpirationPeriod(msg.sender, newSessionExpirationPeriod);

        return true;
    }

}