use ic_protobuf::bitcoin::v1::{
    GetSuccessorsRequest, GetSuccessorsResponse, SendTransactionRequest, SendTransactionResponse,
};
use std::time::Duration;
use tonic::Status;

pub type RpcResult<T> = Result<T, Status>;

pub struct Options {
    pub timeout: Option<Duration>,
}

impl Default for Options {
    fn default() -> Self {
        Self {
            // Since we are allowed to block only for few milliseconds the consensus thread,
            // set reasonable defaults.
            timeout: Some(Duration::from_millis(10)),
        }
    }
}
/// Sync interface for communicating with the bitcoin adapter. Note the function calls block the
/// running thread. Also the calls may panic if called from async context.
pub trait BitcoinAdapterClient {
    fn get_successors(
        &self,
        request: GetSuccessorsRequest,
        opts: Options,
    ) -> RpcResult<GetSuccessorsResponse>;
    fn send_transaction(
        &self,
        request: SendTransactionRequest,
        opts: Options,
    ) -> RpcResult<SendTransactionResponse>;
}
