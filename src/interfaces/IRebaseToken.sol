//SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

interface IRebaseToken {
    function mint(address _to, uint256 _amount, uint256 _userInterestRate) external;
    function burn(address _from, uint256 _amount) external;
    function balanceOf(address _account) external view returns (uint256);
    function getUsersInterestRate(address _user) external view returns (uint256);
    function getInterestRate() external view returns (uint256);
    function grantMintAndBurnRole(address _account) external;
}
