//! Messages protobuf de Quick Share, ecrits a la main (pas de protoc) d'apres
//! les fichiers .proto de Chromium / google/nearby (Apache 2.0) rassembles par
//! NearDrop. Seuls les champs utiles sont declares ; les enumerations sont des
//! entiers (memes octets sur le fil) avec leurs valeurs en constantes.

#![allow(dead_code)]

use prost::Message;

// ------------------------------------------------------------ ukey.proto

pub mod ukey {
    pub const ALERT: i32 = 1;
    pub const CLIENT_INIT: i32 = 2;
    pub const SERVER_INIT: i32 = 3;
    pub const CLIENT_FINISH: i32 = 4;
    pub const P256_SHA512: i32 = 100;
    pub const BAD_MESSAGE: i32 = 1;
    pub const BAD_MESSAGE_TYPE: i32 = 2;
    pub const BAD_MESSAGE_DATA: i32 = 4;
    pub const BAD_VERSION: i32 = 100;
    pub const BAD_RANDOM: i32 = 101;
    pub const BAD_HANDSHAKE_CIPHER: i32 = 102;
    pub const BAD_NEXT_PROTOCOL: i32 = 103;
    pub const NEXT_PROTOCOL: &str = "AES_256_CBC-HMAC_SHA256";
}

#[derive(Clone, PartialEq, Message)]
pub struct Ukey2Message {
    #[prost(int32, optional, tag = "1")]
    pub message_type: Option<i32>,
    #[prost(bytes = "vec", optional, tag = "2")]
    pub message_data: Option<Vec<u8>>,
}

#[derive(Clone, PartialEq, Message)]
pub struct Ukey2Alert {
    #[prost(int32, optional, tag = "1")]
    pub r#type: Option<i32>,
    #[prost(string, optional, tag = "2")]
    pub error_message: Option<String>,
}

#[derive(Clone, PartialEq, Message)]
pub struct CipherCommitment {
    #[prost(int32, optional, tag = "1")]
    pub handshake_cipher: Option<i32>,
    #[prost(bytes = "vec", optional, tag = "2")]
    pub commitment: Option<Vec<u8>>,
}

#[derive(Clone, PartialEq, Message)]
pub struct Ukey2ClientInit {
    #[prost(int32, optional, tag = "1")]
    pub version: Option<i32>,
    #[prost(bytes = "vec", optional, tag = "2")]
    pub random: Option<Vec<u8>>,
    #[prost(message, repeated, tag = "3")]
    pub cipher_commitments: Vec<CipherCommitment>,
    #[prost(string, optional, tag = "4")]
    pub next_protocol: Option<String>,
}

#[derive(Clone, PartialEq, Message)]
pub struct Ukey2ServerInit {
    #[prost(int32, optional, tag = "1")]
    pub version: Option<i32>,
    #[prost(bytes = "vec", optional, tag = "2")]
    pub random: Option<Vec<u8>>,
    #[prost(int32, optional, tag = "3")]
    pub handshake_cipher: Option<i32>,
    #[prost(bytes = "vec", optional, tag = "4")]
    pub public_key: Option<Vec<u8>>,
}

#[derive(Clone, PartialEq, Message)]
pub struct Ukey2ClientFinished {
    #[prost(bytes = "vec", optional, tag = "1")]
    pub public_key: Option<Vec<u8>>,
}

// --------------------------------------------------- securemessage.proto

pub const HMAC_SHA256: i32 = 1;
pub const AES_256_CBC: i32 = 2;
pub const EC_P256: i32 = 1;
/// securegcm.Type.DEVICE_TO_DEVICE_MESSAGE
pub const DEVICE_TO_DEVICE_MESSAGE: i32 = 13;

#[derive(Clone, PartialEq, Message)]
pub struct SecureMessage {
    #[prost(bytes = "vec", required, tag = "1")]
    pub header_and_body: Vec<u8>,
    #[prost(bytes = "vec", required, tag = "2")]
    pub signature: Vec<u8>,
}

#[derive(Clone, PartialEq, Message)]
pub struct Header {
    #[prost(int32, required, tag = "1")]
    pub signature_scheme: i32,
    #[prost(int32, required, tag = "2")]
    pub encryption_scheme: i32,
    #[prost(bytes = "vec", optional, tag = "5")]
    pub iv: Option<Vec<u8>>,
    #[prost(bytes = "vec", optional, tag = "6")]
    pub public_metadata: Option<Vec<u8>>,
}

#[derive(Clone, PartialEq, Message)]
pub struct HeaderAndBody {
    #[prost(message, required, tag = "1")]
    pub header: Header,
    #[prost(bytes = "vec", required, tag = "2")]
    pub body: Vec<u8>,
}

#[derive(Clone, PartialEq, Message)]
pub struct EcP256PublicKey {
    #[prost(bytes = "vec", required, tag = "1")]
    pub x: Vec<u8>,
    #[prost(bytes = "vec", required, tag = "2")]
    pub y: Vec<u8>,
}

#[derive(Clone, PartialEq, Message)]
pub struct GenericPublicKey {
    #[prost(int32, required, tag = "1")]
    pub r#type: i32,
    #[prost(message, optional, tag = "2")]
    pub ec_p256_public_key: Option<EcP256PublicKey>,
}

#[derive(Clone, PartialEq, Message)]
pub struct GcmMetadata {
    #[prost(int32, required, tag = "1")]
    pub r#type: i32,
    #[prost(int32, optional, tag = "2")]
    pub version: Option<i32>,
}

#[derive(Clone, PartialEq, Message)]
pub struct DeviceToDeviceMessage {
    #[prost(bytes = "vec", optional, tag = "1")]
    pub message: Option<Vec<u8>>,
    #[prost(int32, optional, tag = "2")]
    pub sequence_number: Option<i32>,
}

// ---------------------------------------------- offline_wire_formats.proto

pub mod offline {
    pub const V1: i32 = 1;
    pub const CONNECTION_REQUEST: i32 = 1;
    pub const CONNECTION_RESPONSE: i32 = 2;
    pub const PAYLOAD_TRANSFER: i32 = 3;
    pub const BANDWIDTH_UPGRADE_NEGOTIATION: i32 = 4;
    pub const KEEP_ALIVE: i32 = 5;
    pub const DISCONNECTION: i32 = 6;
    pub const MEDIUM_WIFI_LAN: i32 = 5;
    pub const ACCEPT: i32 = 1;
    pub const OS_WINDOWS: i32 = 3;
    pub const PACKET_DATA: i32 = 1;
    pub const PACKET_CONTROL: i32 = 2;
    pub const PAYLOAD_BYTES: i32 = 1;
    pub const PAYLOAD_FILE: i32 = 2;
    pub const LAST_CHUNK: i32 = 1;
    pub const PAYLOAD_CANCELED: i32 = 2;
}

#[derive(Clone, PartialEq, Message)]
pub struct OfflineFrame {
    #[prost(int32, optional, tag = "1")]
    pub version: Option<i32>,
    #[prost(message, optional, tag = "2")]
    pub v1: Option<V1Frame>,
}

#[derive(Clone, PartialEq, Message)]
pub struct V1Frame {
    #[prost(int32, optional, tag = "1")]
    pub r#type: Option<i32>,
    #[prost(message, optional, tag = "2")]
    pub connection_request: Option<ConnectionRequestFrame>,
    #[prost(message, optional, tag = "3")]
    pub connection_response: Option<ConnectionResponseFrame>,
    #[prost(message, optional, tag = "4")]
    pub payload_transfer: Option<PayloadTransferFrame>,
    #[prost(message, optional, tag = "6")]
    pub keep_alive: Option<KeepAliveFrame>,
    #[prost(message, optional, tag = "7")]
    pub disconnection: Option<DisconnectionFrame>,
}

#[derive(Clone, PartialEq, Message)]
pub struct ConnectionRequestFrame {
    #[prost(string, optional, tag = "1")]
    pub endpoint_id: Option<String>,
    #[prost(string, optional, tag = "2")]
    pub endpoint_name: Option<String>,
    #[prost(int32, repeated, packed = "false", tag = "5")]
    pub mediums: Vec<i32>,
    #[prost(bytes = "vec", optional, tag = "6")]
    pub endpoint_info: Option<Vec<u8>>,
}

#[derive(Clone, PartialEq, Message)]
pub struct OsInfo {
    #[prost(int32, optional, tag = "1")]
    pub r#type: Option<i32>,
}

#[derive(Clone, PartialEq, Message)]
pub struct ConnectionResponseFrame {
    #[prost(int32, optional, tag = "1")]
    pub status: Option<i32>,
    #[prost(int32, optional, tag = "3")]
    pub response: Option<i32>,
    #[prost(message, optional, tag = "4")]
    pub os_info: Option<OsInfo>,
}

#[derive(Clone, PartialEq, Message)]
pub struct PayloadHeader {
    #[prost(int64, optional, tag = "1")]
    pub id: Option<i64>,
    #[prost(int32, optional, tag = "2")]
    pub r#type: Option<i32>,
    #[prost(int64, optional, tag = "3")]
    pub total_size: Option<i64>,
    #[prost(bool, optional, tag = "4")]
    pub is_sensitive: Option<bool>,
}

#[derive(Clone, PartialEq, Message)]
pub struct PayloadChunk {
    #[prost(int32, optional, tag = "1")]
    pub flags: Option<i32>,
    #[prost(int64, optional, tag = "2")]
    pub offset: Option<i64>,
    #[prost(bytes = "vec", optional, tag = "3")]
    pub body: Option<Vec<u8>>,
}

#[derive(Clone, PartialEq, Message)]
pub struct ControlMessage {
    #[prost(int32, optional, tag = "1")]
    pub event: Option<i32>,
    #[prost(int64, optional, tag = "2")]
    pub offset: Option<i64>,
}

#[derive(Clone, PartialEq, Message)]
pub struct PayloadTransferFrame {
    #[prost(int32, optional, tag = "1")]
    pub packet_type: Option<i32>,
    #[prost(message, optional, tag = "2")]
    pub payload_header: Option<PayloadHeader>,
    #[prost(message, optional, tag = "3")]
    pub payload_chunk: Option<PayloadChunk>,
    #[prost(message, optional, tag = "4")]
    pub control_message: Option<ControlMessage>,
}

#[derive(Clone, PartialEq, Message)]
pub struct KeepAliveFrame {
    #[prost(bool, optional, tag = "1")]
    pub ack: Option<bool>,
}

#[derive(Clone, PartialEq, Message)]
pub struct DisconnectionFrame {
    #[prost(bool, optional, tag = "1")]
    pub request_safe_to_disconnect: Option<bool>,
}

// ------------------------------------------------------ wire_format.proto

pub mod sharing {
    pub const V1: i32 = 1;
    pub const INTRODUCTION: i32 = 1;
    pub const RESPONSE: i32 = 2;
    pub const PAIRED_KEY_ENCRYPTION: i32 = 3;
    pub const PAIRED_KEY_RESULT: i32 = 4;
    pub const CANCEL: i32 = 6;
    // FileMetadata.Type
    pub const FILE_UNKNOWN: i32 = 0;
    pub const FILE_IMAGE: i32 = 1;
    pub const FILE_VIDEO: i32 = 2;
    pub const FILE_APP: i32 = 3;
    pub const FILE_AUDIO: i32 = 4;
    pub const FILE_DOCUMENT: i32 = 5;
    // TextMetadata.Type
    pub const TEXT: i32 = 1;
    pub const URL: i32 = 2;
    pub const ADDRESS: i32 = 3;
    pub const PHONE_NUMBER: i32 = 4;
    // ConnectionResponseFrame.Status
    pub const ACCEPT: i32 = 1;
    pub const REJECT: i32 = 2;
    pub const NOT_ENOUGH_SPACE: i32 = 3;
    pub const UNSUPPORTED_ATTACHMENT_TYPE: i32 = 4;
    pub const TIMED_OUT: i32 = 5;
    // PairedKeyResultFrame.Status
    pub const UNABLE: i32 = 3;
}

#[derive(Clone, PartialEq, Message)]
pub struct FileMetadata {
    #[prost(string, optional, tag = "1")]
    pub name: Option<String>,
    #[prost(int32, optional, tag = "2")]
    pub r#type: Option<i32>,
    #[prost(int64, optional, tag = "3")]
    pub payload_id: Option<i64>,
    #[prost(int64, optional, tag = "4")]
    pub size: Option<i64>,
    #[prost(string, optional, tag = "5")]
    pub mime_type: Option<String>,
    #[prost(int64, optional, tag = "6")]
    pub id: Option<i64>,
}

#[derive(Clone, PartialEq, Message)]
pub struct TextMetadata {
    #[prost(string, optional, tag = "2")]
    pub text_title: Option<String>,
    #[prost(int32, optional, tag = "3")]
    pub r#type: Option<i32>,
    #[prost(int64, optional, tag = "4")]
    pub payload_id: Option<i64>,
    #[prost(int64, optional, tag = "5")]
    pub size: Option<i64>,
    #[prost(int64, optional, tag = "6")]
    pub id: Option<i64>,
}

#[derive(Clone, PartialEq, Message)]
pub struct WifiCredentialsMetadata {
    #[prost(string, optional, tag = "2")]
    pub ssid: Option<String>,
    #[prost(int32, optional, tag = "3")]
    pub security_type: Option<i32>,
    #[prost(int64, optional, tag = "4")]
    pub payload_id: Option<i64>,
    #[prost(int64, optional, tag = "5")]
    pub id: Option<i64>,
}

#[derive(Clone, PartialEq, Message)]
pub struct WifiCredentials {
    #[prost(string, optional, tag = "1")]
    pub password: Option<String>,
    #[prost(bool, optional, tag = "2")]
    pub hidden_ssid: Option<bool>,
}

#[derive(Clone, PartialEq, Message)]
pub struct IntroductionFrame {
    #[prost(message, repeated, tag = "1")]
    pub file_metadata: Vec<FileMetadata>,
    #[prost(message, repeated, tag = "2")]
    pub text_metadata: Vec<TextMetadata>,
    #[prost(message, repeated, tag = "4")]
    pub wifi_credentials_metadata: Vec<WifiCredentialsMetadata>,
    #[prost(bool, optional, tag = "6")]
    pub start_transfer: Option<bool>,
}

#[derive(Clone, PartialEq, Message)]
pub struct SharingResponseFrame {
    #[prost(int32, optional, tag = "1")]
    pub status: Option<i32>,
}

#[derive(Clone, PartialEq, Message)]
pub struct PairedKeyEncryptionFrame {
    #[prost(bytes = "vec", optional, tag = "1")]
    pub signed_data: Option<Vec<u8>>,
    #[prost(bytes = "vec", optional, tag = "2")]
    pub secret_id_hash: Option<Vec<u8>>,
    #[prost(bytes = "vec", optional, tag = "4")]
    pub qr_code_handshake_data: Option<Vec<u8>>,
}

#[derive(Clone, PartialEq, Message)]
pub struct PairedKeyResultFrame {
    #[prost(int32, optional, tag = "1")]
    pub status: Option<i32>,
}

#[derive(Clone, PartialEq, Message)]
pub struct SharingV1Frame {
    #[prost(int32, optional, tag = "1")]
    pub r#type: Option<i32>,
    #[prost(message, optional, tag = "2")]
    pub introduction: Option<IntroductionFrame>,
    #[prost(message, optional, tag = "3")]
    pub connection_response: Option<SharingResponseFrame>,
    #[prost(message, optional, tag = "4")]
    pub paired_key_encryption: Option<PairedKeyEncryptionFrame>,
    #[prost(message, optional, tag = "5")]
    pub paired_key_result: Option<PairedKeyResultFrame>,
}

#[derive(Clone, PartialEq, Message)]
pub struct SharingFrame {
    #[prost(int32, optional, tag = "1")]
    pub version: Option<i32>,
    #[prost(message, optional, tag = "2")]
    pub v1: Option<SharingV1Frame>,
}

impl SharingFrame {
    pub fn v1(f: SharingV1Frame) -> Self {
        SharingFrame { version: Some(sharing::V1), v1: Some(f) }
    }
    pub fn kind(&self) -> i32 {
        self.v1.as_ref().and_then(|v| v.r#type).unwrap_or(0)
    }
}

impl OfflineFrame {
    pub fn v1(f: V1Frame) -> Self {
        OfflineFrame { version: Some(offline::V1), v1: Some(f) }
    }
    pub fn kind(&self) -> i32 {
        self.v1.as_ref().and_then(|v| v.r#type).unwrap_or(0)
    }
}
