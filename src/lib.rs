use anchor_lang::{
  prelude::*,
  system_program::{create_account, CreateAccount},
};
use anchor_spl::{
  associated_token::AssociatedToken,
  token_interface::{Mint, TokenAccount, TokenInterface},
};
use spl_tlv_account_resolution::{
  state::ExtraAccountMetaList,
  account::ExtraAccountMeta,
};
use spl_transfer_hook_interface::instruction::{ExecuteInstruction, TransferHookInstruction};
use solana_program::{
    sysvar::instructions::{load_current_index_checked, load_instruction_at_checked},
};

// Token Mint account using this hook program 6NBsYsoj5aRt7X9cmUksv8aeLtubErmLkGZ8DujrtoS3
// Hook program ID:
declare_id!("B2tN85yQ3ta8965WYns4DnitH9YJ9JnBsPb1dF1ghb15");


// Token-2022 Program ID
// echo "TokenzQdBNbLqP5VEhdkAS6EPFLC1PHnBqCXEpPxuEb" | python3 -c "import base58; print([hex(x) for x in base58.b58decode(input())])"
pub const TOKEN_2022_PROGRAM_ID: Pubkey = Pubkey::new_from_array([
    0x6, 0xdd, 0xf6, 0xe1, 0xee, 0x75, 0x8f, 0xde, 0x18, 0x42, 0x5d, 0xbc, 0xe4, 0x6c, 0xcd, 0xda,
    0xb6, 0x1a, 0xfc, 0x4d, 0x83, 0xb9, 0xd, 0x27, 0xfe, 0xbd, 0xf9, 0x28, 0xd8, 0xa1, 0x8b, 0xfc
]);

#[error_code]
pub enum ErrorCode {
    #[msg("Caller is not authorized to invoke this instruction")]
    UnauthorizedCaller,
    #[msg("Invalid instruction data")]
    InvalidInstruction,
}

#[program]
pub mod transfer_hook {
  use super::*;

  pub fn initialize_extra_account_meta_list(
      ctx: Context<InitializeExtraAccountMetaList>,
  ) -> Result<()> {

      // The `addExtraAccountsToInstruction` JS helper function resolving incorrectly
      let account_metas = vec![
          // Include the instructions sysvar account
          ExtraAccountMeta::new_with_pubkey(
              &solana_program::sysvar::instructions::ID,
              false,
              false,
          )?,
      ];

      // calculate account size
      let account_size = ExtraAccountMetaList::size_of(account_metas.len())? as u64;
      // calculate minimum required lamports
      let lamports = Rent::get()?.minimum_balance(account_size as usize);

      let mint = ctx.accounts.mint.key();
      let signer_seeds: &[&[&[u8]]] = &[&[
          b"extra-account-metas",
          &mint.as_ref(),
          &[ctx.bumps.extra_account_meta_list],
      ]];

      // create ExtraAccountMetaList account
      create_account(
          CpiContext::new(
              ctx.accounts.system_program.to_account_info(),
              CreateAccount {
                  from: ctx.accounts.payer.to_account_info(),
                  to: ctx.accounts.extra_account_meta_list.to_account_info(),
              },
          )
          .with_signer(signer_seeds),
          lamports,
          account_size,
          ctx.program_id,
      )?;

      // initialize ExtraAccountMetaList account with extra accounts
      ExtraAccountMetaList::init::<ExecuteInstruction>(
          &mut ctx.accounts.extra_account_meta_list.try_borrow_mut_data()?,
          &account_metas,
      )?;

      Ok(())
  }

  pub fn transfer_hook(_ctx: Context<TransferHook>, _amount: u64) -> Result<()> {

      // TODO: human verification logic

      Ok(())
  }

  // fallback instruction handler as workaround to anchor instruction discriminator check
  pub fn fallback<'info>(
      program_id: &Pubkey,
      accounts: &'info [AccountInfo<'info>],
      data: &[u8],
  ) -> Result<()> {
      // Get the instructions sysvar account (last account)
      let instructions_sysvar_info = accounts.last().unwrap();

      // Verify we're being called via CPI and by the token program
      let current_ix_index = load_current_index_checked(instructions_sysvar_info)?;
      if current_ix_index == 0 {
          return err!(ErrorCode::UnauthorizedCaller);
      }

      // Check that the caller is the Token-2022 program
      let caller_ix = load_instruction_at_checked(current_ix_index as usize, instructions_sysvar_info)?;
      if caller_ix.program_id != TOKEN_2022_PROGRAM_ID {
          return err!(ErrorCode::UnauthorizedCaller);
      }

      let instruction = TransferHookInstruction::unpack(data)?;

      // match instruction discriminator to transfer hook interface execute instruction  
      // token2022 program CPIs this instruction on token transfer
      match instruction {
          TransferHookInstruction::Execute { amount } => {
              let amount_bytes = amount.to_le_bytes();

              // invoke custom transfer hook instruction on our program
              __private::__global::transfer_hook(program_id, accounts, &amount_bytes)
          }
          _ => return err!(ErrorCode::InvalidInstruction),
      }
  }
}

#[derive(Accounts)]
pub struct InitializeExtraAccountMetaList<'info> {
  #[account(mut)]
  payer: Signer<'info>,

  /// CHECK: ExtraAccountMetaList Account, must use these seeds
  #[account(
      mut,
      seeds = [b"extra-account-metas", mint.key().as_ref()], 
      bump
  )]
  pub extra_account_meta_list: AccountInfo<'info>,
  pub mint: InterfaceAccount<'info, Mint>,
  pub token_program: Interface<'info, TokenInterface>,
  pub associated_token_program: Program<'info, AssociatedToken>,
  pub system_program: Program<'info, System>,
}

// Order of accounts matters for this struct.
// The first 4 accounts are the accounts required for token transfer (source, mint, destination, owner)
// Remaining accounts are the extra accounts required from the ExtraAccountMetaList account
// These accounts are provided via CPI to this program from the token2022 program
#[derive(Accounts)]
pub struct TransferHook<'info> {
  #[account(
      token::mint = mint, 
      token::authority = owner,
  )]
  pub source_token: InterfaceAccount<'info, TokenAccount>,
  pub mint: InterfaceAccount<'info, Mint>,
  #[account(
      token::mint = mint,
  )]
  pub destination_token: InterfaceAccount<'info, TokenAccount>,
  /// CHECK: source token account owner, can be SystemAccount or PDA owned by another program
  pub owner: UncheckedAccount<'info>,
  /// CHECK: ExtraAccountMetaList Account,
  #[account(
      seeds = [b"extra-account-metas", mint.key().as_ref()], 
      bump
  )]
  pub extra_account_meta_list: UncheckedAccount<'info>,
  /// CHECK: Instructions sysvar account used to verify CPI caller
  #[account(address = solana_program::sysvar::instructions::ID)]
  pub instructions_sysvar: AccountInfo<'info>,
}
