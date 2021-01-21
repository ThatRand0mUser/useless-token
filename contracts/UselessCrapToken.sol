// SPDX-License-Identifier: MIT
pragma solidity ^0.6.2;

import "https://github.com/OpenZeppelin/openzeppelin-contracts/blob/v3.3.0/contracts/token/ERC20/ERC20.sol";
import "https://github.com/smartcontractkit/chainlink/blob/master/evm-contracts/src/v0.6/interfaces/AggregatorV3Interface.sol";
import "https://raw.githubusercontent.com/smartcontractkit/chainlink/master/evm-contracts/src/v0.6/VRFConsumerBase.sol";

/*
    UselessCrap Token (CRAP)

    ERC20 Test token on Ethereum blockchain leverages chainlink (LINK) price oracle and the new chainlink VRF to get random verified numbers.
    
    This token rebalances every hour and affect tokens that are locked on the contract.
    When rebalance mechanism activates:
        * Requests a random number to be generated by the chainlink VRF
        * When the random number arrives get the current price of BTC/ETH pair using chainlink price oracle
        * If new price is greater than the price at the previous rebalance: Mint random % of tokens for each account that have locked tokens. 
        * If new price is less than the price at the previous rebalance: Burn random % of tokens on each account that have locked tokens.
*/

contract UselessCrap is ERC20 {
    constructor () public ERC20("UselessCrap", "CRAP") {
        _mint(msg.sender, 1000000 * (10 ** uint256(decimals())));
    }
}

contract UselessCrapExecutor is VRFConsumerBase, UselessCrap  {
    bytes32 internal keyHash;
    uint256 internal fee;
    uint256 public randomPercentage;
    
    AggregatorV3Interface internal priceFeed;
    
    int public basePrice;
    address[] public _lockedAddresses;
    struct balancesData {
        uint8 addressIndex;
        uint256 balance;
        bool exists;
    }
    mapping (address => balancesData) public _lockedBalances;
    
    /**
     * Network: Kovan
     * Aggregator: BTC/ETH
     * Address: 0xF7904a295A029a3aBDFFB6F12755974a958C7C25
    */
    
    /**
     * Constructor inherits VRFConsumerBase
     * 
     * Network: Kovan
     * Chainlink VRF Coordinator address: 0xdD3782915140c8f3b190B5D67eAc6dc5760C46E9
     * LINK token address:                0xa36085F69e2889c224210F603D836748e7dC0088
     * Key Hash: 0x6c3699283bda56ad74f6b855546325b68d482e983852a7a82979cc4807b641f4
     */
    constructor() 
        VRFConsumerBase(
            0xdD3782915140c8f3b190B5D67eAc6dc5760C46E9, // VRF Coordinator
            0xa36085F69e2889c224210F603D836748e7dC0088  // LINK Token
        ) public
    {
        keyHash = 0x6c3699283bda56ad74f6b855546325b68d482e983852a7a82979cc4807b641f4;
        fee = 0.1 * 10 ** 18; // 0.1 LINK
        priceFeed = AggregatorV3Interface(0xF7904a295A029a3aBDFFB6F12755974a958C7C25);
        basePrice = 27549119243458275000;
    }
    
    /**
     * LOCK TOKENS
     *  - User transfers the tokens that want to lock to the contract
    */
    function lockTokens(uint256 amount) public returns (bool) {
        _transfer(_msgSender(), address(this), amount);
        if(_lockedBalances[_msgSender()].exists == false) {
            _lockedAddresses.push(_msgSender());
            _lockedBalances[_msgSender()].addressIndex = uint8(_lockedAddresses.length) - 1;
            _lockedBalances[_msgSender()].exists = true;
        }
        _lockedBalances[_msgSender()].balance = _lockedBalances[_msgSender()].balance + amount;
        return true;
    }
    
    /**
     * WITHDRAW LOCKED TOKENS
     *  - User withdraws the amount of tokens locked specified to his address
    */
    function withdrawLockedTokens(uint256 amount) public returns (bool) {
        _transfer(address(this), _msgSender(), amount);
        _lockedBalances[_msgSender()].balance = _lockedBalances[_msgSender()].balance - amount;
        if(_lockedBalances[_msgSender()].balance == 0) {
            for (uint i = _lockedBalances[_msgSender()].addressIndex; i<_lockedAddresses.length-1; i++){
                _lockedAddresses[i] = _lockedAddresses[i+1];
            }
            delete _lockedAddresses[_lockedAddresses.length-1];
            _lockedAddresses.pop();
            delete _lockedBalances[_msgSender()];
        }
        return true;
    }
    
    /**
     * REBALANCE TRIGGER
     */
    function rebalanceTrigger(uint256 userProvidedSeed) public returns (bytes32 requestId) {
        require(LINK.balanceOf(address(this)) > fee, "Not enough LINK - fill contract with faucet");
        return requestRandomness(keyHash, fee, userProvidedSeed);
    }

    /**
     * Callback function used by VRF Coordinator
     */
    function fulfillRandomness(bytes32 requestId, uint256 randomness) internal override {
        randomPercentage = randomness % 30; // percentage cannot be greatter than 30%
        int newPrice = getLatestPrice();
        if (newPrice > basePrice){ // It means ETH is up in relation to BTC => MINT
            for(uint8 i=0; i<= _lockedAddresses.length - 1; i++){
                uint256 mintQuantity = _lockedBalances[_lockedAddresses[i]].balance * randomPercentage / 100;
                _lockedBalances[_lockedAddresses[i]].balance = _lockedBalances[_lockedAddresses[i]].balance + mintQuantity;
                _mint(address(this),mintQuantity);
            }
        }
        else if (newPrice < basePrice){ // It means BTC is up in relation to ETH => BURN
            for(uint8 i=0; i<= _lockedAddresses.length - 1; i++){
                uint256 burnQuantity = _lockedBalances[_lockedAddresses[i]].balance * randomPercentage / 100;
                _lockedBalances[_lockedAddresses[i]].balance = _lockedBalances[_lockedAddresses[i]].balance - burnQuantity;
                _burn(address(this),burnQuantity);
            }
        }
        basePrice = getLatestPrice();
    }
     
    function getLatestPrice() public view returns (int) {
        (
            uint80 roundID, 
            int price,
            uint startedAt,
            uint timeStamp,
            uint80 answeredInRound
        ) = priceFeed.latestRoundData();
        return (price);
    }
    
    function getAddresses() public view returns (address[] memory) {
        return (_lockedAddresses);
    }

    function getLockBalanceOf(address account) public view returns (uint256) {
        return (_lockedBalances[account].balance);
    }
}