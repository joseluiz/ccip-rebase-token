//SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";
/**
 * @title RebaseToken
 * @author José Luiz Silveira
 * @notice This is cross-chain rebase token that incentivises users to deposit into a vault and gain interest in rewards.
 * @notice The interest rate in the smart contract can only decrease.
 * @notice Each user will have their own interest rate that is the global interest rate at the time of deposit.
 */

contract RebaseToken is ERC20, Ownable, AccessControl {
    error RabaseToken__InterestRateCanOnlyDecrease(uint256 oldInterestRate, uint256 newInterestRate);

    uint256 private constant PRECISION_FACTOR = 1e18;
    bytes32 private constant MINT_AND_BURN_ROLE = keccak256("MINT_AND_BURN_ROLE");

    uint256 private _interestRate = (5 * PRECISION_FACTOR) / 1e8; //10^-8 == 1 / 10^8
    mapping(address => uint256) private s_usersInterestRate;
    mapping(address => uint256) private s_usersLastUpdatedTimestamp;

    event InterestRateSet(uint256 newInterestRate);

    constructor() ERC20("RebaseToken", "RBT") Ownable(msg.sender) {}

    function grantMintAndBurnRole(address _account) external onlyOwner {
        _grantRole(MINT_AND_BURN_ROLE, _account);
    }

    /**
     * @notice Set the interest rate in the contract.
     * @param _newInterestRate The new interest rate to set.
     * @dev The interest rate can only decrease.
     */
    function setInterestRate(uint256 _newInterestRate) external onlyOwner {
        if (_newInterestRate >= _interestRate) {
            revert RabaseToken__InterestRateCanOnlyDecrease(_interestRate, _newInterestRate);
        }
        _interestRate = _newInterestRate;
        emit InterestRateSet(_newInterestRate);
    }

    /**
     * @notice Get the principal balance of a user. This is the number of tokens that have currently been minted to the user, not including the interest that has accrued since the last time user interacted with the protocol.
     * @param _user The address of the user to get the principal balance for.
     * @return The principal balance of the user.
     */
    function principalBalanceOf(address _user) public view returns (uint256) {
        return super.balanceOf(_user);
    }

    /**
     * @notice Mint the user tokens when they deposit into the vault.
     * @param _to The address of the user to mint the tokens to.
     * @param _amount The amount of tokens to mint.
     * @param _userInterestRate The interest rate for the user.
     */
    function mint(address _to, uint256 _amount, uint256 _userInterestRate) external onlyRole(MINT_AND_BURN_ROLE) {
        _mintAccruedInterest(_to);
        s_usersInterestRate[_to] = _userInterestRate;
        _mint(_to, _amount);
    }

    /**
     * @notice Burn the user tokens when they withdraw from the vault.
     * @param _from The address of the user to burn the tokens from.
     * @param _amount The amount of tokens to burn.
     */
    function burn(address _from, uint256 _amount) external onlyRole(MINT_AND_BURN_ROLE) {
        _mintAccruedInterest(_from);
        _burn(_from, _amount);
    }

    /**
     * @notice Calculate the balance for the user including the interest that has accumulated since the last update.
     * (principle balance) + some interest that has accrued.
     * @param _user The address of the user to calculate the balance for.
     * @return The balance of the user including the interest rate.
     */
    function balanceOf(address _user) public view override returns (uint256) {
        return (super.balanceOf(_user) * _calculateUserAccumulatedInterestSinceLastUpdate(_user)) / PRECISION_FACTOR;
    }

    /**
     * @notice Transfer tokens from one user to another.
     * @param _recipient The address of the user to transfer the tokens to.
     * @param _amount The amount of tokens to transfer.
     * @return bool True if the transfer was successful.
     */
    function transfer(address _recipient, uint256 _amount) public override returns (bool) {
        _mintAccruedInterest(msg.sender);
        _mintAccruedInterest(_recipient);
        if (_amount == type(uint256).max) {
            _amount = balanceOf(msg.sender);
        }
        if (balanceOf(_recipient) == 0) {
            s_usersInterestRate[_recipient] = s_usersInterestRate[msg.sender];
        }
        return super.transfer(_recipient, _amount);
    }

    /**
     * @notice Transfer tokens from one user to another.
     * @param _sender The address of the user to transfer the tokens from.
     * @param _recipient The address of the user to transfer the tokens to.
     * @param _amount The amount of tokens to transfer.
     * @return bool True if the transfer was successful.
     */
    function transferFrom(address _sender, address _recipient, uint256 _amount) public override returns (bool) {
        _mintAccruedInterest(_sender);
        _mintAccruedInterest(_recipient);
        if (_amount == type(uint256).max) {
            _amount = balanceOf(_sender);
        }
        if (balanceOf(_recipient) == 0) {
            s_usersInterestRate[_recipient] = s_usersInterestRate[_sender];
        }
        return super.transferFrom(_sender, _recipient, _amount);
    }

    /**
     * @notice Calculate the interest that has accumulated since the last update.
     * @param _user The address of the user to calculate the interest for.
     * @return linearInterest The interest that has accumulated since the last update.
     */
    function _calculateUserAccumulatedInterestSinceLastUpdate(address _user)
        internal
        view
        returns (uint256 linearInterest)
    {
        uint256 timeElapsed = block.timestamp - s_usersLastUpdatedTimestamp[_user];
        linearInterest = PRECISION_FACTOR + (s_usersInterestRate[_user] * timeElapsed);
    }

    /**
     * @notice Mint the accrued interest to the user since the last time they interacted with the protocol.
     * @param _user The address of the user to mint the interest for.
     */
    function _mintAccruedInterest(address _user) internal {
        uint256 previousPrincipleBalance = super.balanceOf(_user);
        uint256 currentBalance = balanceOf(_user);
        uint256 balanceIncrease = currentBalance - previousPrincipleBalance;
        s_usersLastUpdatedTimestamp[_user] = block.timestamp;
        _mint(_user, balanceIncrease);
    }

    /**
     * @notice Get the global interest rate that is currently set in the contract.
     * @return The global interest rate.
     */
    function getInterestRate() external view returns (uint256) {
        return _interestRate;
    }

    /**
     * @notice Get the interest rate for a user.
     * @param _user The address of the user.
     * @return The interest rate for the user.
     */
    function getUsersInterestRate(address _user) external view returns (uint256) {
        return s_usersInterestRate[_user];
    }
}
