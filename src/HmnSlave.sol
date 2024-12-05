// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {IERC165} from "@openzeppelin/contracts/utils/introspection/IERC165.sol";
import {IOptimismMintableERC20} from "./interfaces/IOptimismMintableERC20.sol";
import {HmnBase} from "./HmnBase.sol";
import {IHmnManagerBase} from "./interfaces/IHmnManagerBase.sol";
import {IArbToken} from "./interfaces/IArbitrum.sol";
import {IHmnSlave} from "./interfaces/IHmnSlave.sol";


contract HmnSlave is HmnBase, IHmnSlave, IOptimismMintableERC20, IArbToken {

    ///////////////////////////////////////////////////////////////////////////////
    ///                                  Storage                                ///
    ///////////////////////////////////////////////////////////////////////////////

    /// @notice Address of the corresponding version of this token on the remote chain.
    address public immutable REMOTE_TOKEN;
 
    /// @notice Address of the StandardBridge on this network.
    address public immutable BRIDGE;

    ///////////////////////////////////////////////////////////////////////////////
    ///                             Events & Errors                             ///
    ///////////////////////////////////////////////////////////////////////////////

    /// @notice Emitted whenever tokens are minted for an account.
    /// @param account Address of the account tokens are being minted for.
    /// @param amount  Amount of tokens minted.
    event Mint(address indexed account, uint256 amount);
 
    /// @notice Emitted whenever tokens are burned from an account.
    /// @param account Address of the account tokens are being burned from.
    /// @param amount  Amount of tokens burned.
    event Burn(address indexed account, uint256 amount);

    event AccountRecoveryApproved(address indexed from, address indexed to);

    error Unauthorised(address caller);

    ///////////////////////////////////////////////////////////////////////////////
    ///                                Modifiers                                ///
    ///////////////////////////////////////////////////////////////////////////////

    /// @notice A modifier that only allows the bridge to call.
    modifier onlyTokenBridge() {
        if (_msgSender() != BRIDGE) revert Unauthorised(_msgSender());
        _;
    }
    
    /// @notice A modifier that only allows the transfer control contract to call.
    modifier onlyManager() {
        if (_msgSender() != address(hmnManager)) revert Unauthorised(_msgSender());
        _;
    }

    ///////////////////////////////////////////////////////////////////////////////
    ///                             Initialization                              ///
    ///////////////////////////////////////////////////////////////////////////////

    constructor(
      address _remoteToken,
      address _bridge,
      IHmnManagerBase _hmnManager
    ) HmnBase(_hmnManager) {
        REMOTE_TOKEN = _remoteToken;
        BRIDGE = _bridge;
    }

    ///////////////////////////////////////////////////////////////////////////////
    ///                              Recovery feature                           ///
    ///////////////////////////////////////////////////////////////////////////////

    /// @notice Enables or disables account recovery for the caller in this particular L2 chain.
    ///         For safety, recovery has to be explicity enabled in each L2 chain.
    /// @param enable Boolean flag to enable or disable recovery.
    function enableRecovery(bool enable) external virtual {
        addressRecoveryEnabled[_msgSender()] = enable;
    }

    /// @notice Approve lost tokens for recovery after authnetication via the L1 Transfer Control Registry.
    ///         Note, that recovery has to be explicitly enabled before hand in each chain.
    /// @dev Can only be called by the transfer control contract and if recovery is enabled.
    /// @param fromAddress The address to recover tokens from.
    /// @param toAddress The address to recover tokens to.
    function recover(address fromAddress, address toAddress) external virtual onlyManager {
        if (!addressRecoveryEnabled[_msgSender()]) revert Unauthorised(_msgSender());
        _approve(fromAddress, toAddress, balanceOf(fromAddress));
        emit AccountRecoveryApproved(fromAddress, toAddress);
    }

    ///////////////////////////////////////////////////////////////////////////////
    ///                         IOptimismMintableERC20                          ///
    ///////////////////////////////////////////////////////////////////////////////

    /// @inheritdoc IOptimismMintableERC20
    /// @custom:legacy
    function remoteToken() public view returns (address) {
        return REMOTE_TOKEN;
    }
 
    /// @inheritdoc IOptimismMintableERC20
    /// @custom:legacy
    function bridge() public view returns (address) {
        return BRIDGE;
    }

    /// @notice Checks if the contract supports a given interface.
    /// @param _interfaceId The interface identifier, as specified in ERC-165.
    /// @return True if the contract implements the specified interface.
    function supportsInterface(bytes4 _interfaceId) public view virtual override(HmnBase, IERC165) returns (bool) {
        bytes4 erc165 = type(IERC165).interfaceId;
        bytes4 iMintable = type(IOptimismMintableERC20).interfaceId;
        return _interfaceId == erc165 || _interfaceId == iMintable || super.supportsInterface(_interfaceId);
    }

    /// @notice Allows the StandardBridge to mint tokens.
    /// @dev Restricted to only be called by the token bridge.
    /// @param _to     The address to mint tokens to.
    /// @param _amount The amount of tokens to mint.
    function mint(
        address _to,
        uint256 _amount
    )
        public
        virtual
        override(IOptimismMintableERC20)
        onlyTokenBridge
    {
        _mint(_to, _amount);
        emit Mint(_to, _amount);
    }
 
    /// @notice Allows the StandardBridge to burn tokens.
    /// @dev Restricted to only be called by the token bridge.
    /// @param _from   The address to burn tokens from.
    /// @param _amount The amount of tokens to burn.
    function burn(address _from, uint256 _amount)
        public
        virtual
        override(IOptimismMintableERC20)
        onlyTokenBridge
    {
        _burn(_from, _amount);
        emit Burn(_from, _amount);
    }

    ///////////////////////////////////////////////////////////////////////////////
    ///                             IArbToken                                   ///
    ///////////////////////////////////////////////////////////////////////////////

    /**
     * @notice Mints tokens to an account via the bridge.
     * @dev Restricted to only be called by the token bridge.
     * @param account The address to mint tokens to.
     * @param amount  The amount of tokens to mint.
     */
    function bridgeMint(address account, uint256 amount) external virtual override(IArbToken) onlyTokenBridge {
      mint(account, amount);
    }

    /**
     * @notice Burns tokens from an account via the bridge.
     * @dev Restricted to only be called by the token bridge.
     * @param account The address to burn tokens from.
     * @param amount  The amount of tokens to burn.
     */
    function bridgeBurn(address account, uint256 amount) external virtual override(IArbToken) onlyTokenBridge {
      burn(account, amount);
    }

    /**
     * @notice Returns the address of the corresponding L1 token.
     * @return The L1 token address.
     */
    function l1Address() public view virtual returns (address) {
      return REMOTE_TOKEN;
    }

    /**
     * @notice Returns the address of the bridge contract.
     * @return The bridge contract address.
     */
    function l2Gateway() public view virtual returns (address) {
      return BRIDGE;
    }

}
