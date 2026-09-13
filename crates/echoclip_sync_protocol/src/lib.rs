use std::fmt;

use base64::Engine;
use base64::engine::general_purpose::{STANDARD, URL_SAFE_NO_PAD};
use chacha20poly1305::aead::{Aead, KeyInit, Payload};
use chacha20poly1305::{ChaCha20Poly1305, Key, Nonce};
use hkdf::Hkdf;
use rand::RngCore;
use serde::{Deserialize, Serialize};
use sha2::{Digest, Sha256};
use zeroize::{Zeroize, ZeroizeOnDrop};

pub const PROTOCOL_VERSION: u8 = 2;
pub const ENVELOPE_MAGIC: [u8; 4] = *b"ECS1";
pub const SAMPLE_FORMAT_PCM_S16LE: &str = "pcm_s16le";
pub const KEY_BYTES: usize = 32;
pub const ID_BYTES: usize = 16;
pub const AEAD_TAG_BYTES: usize = 16;
pub const MAX_KEY_ID_BYTES: usize = 64;
pub const MAX_STRING_BYTES: usize = 4096;
pub const MAX_PCM_SAMPLES: usize = 128 * 1024;

const C2S_INFO: &[u8] = b"echoclip-upload-v1-c2s";
const S2C_INFO: &[u8] = b"echoclip-upload-v1-s2c";
const C2S_DOMAIN: u32 = 0x4332_5301;
const S2C_DOMAIN: u32 = 0x5332_4301;

#[derive(Debug)]
pub enum ProtocolError {
    InvalidKey,
    InvalidBase64,
    InvalidEnvelope(&'static str),
    InvalidMessage(&'static str),
    AuthenticationFailed,
    KdfFailed,
    LimitExceeded(&'static str),
    Utf8,
}

impl fmt::Display for ProtocolError {
    fn fmt(&self, formatter: &mut fmt::Formatter<'_>) -> fmt::Result {
        match self {
            Self::InvalidKey => write!(formatter, "invalid upload key"),
            Self::InvalidBase64 => write!(formatter, "invalid base64"),
            Self::InvalidEnvelope(message) => write!(formatter, "invalid envelope: {message}"),
            Self::InvalidMessage(message) => write!(formatter, "invalid message: {message}"),
            Self::AuthenticationFailed => write!(formatter, "message authentication failed"),
            Self::KdfFailed => write!(formatter, "session key derivation failed"),
            Self::LimitExceeded(name) => write!(formatter, "protocol limit exceeded: {name}"),
            Self::Utf8 => write!(formatter, "invalid UTF-8"),
        }
    }
}

impl std::error::Error for ProtocolError {}

#[derive(Clone, Zeroize, ZeroizeOnDrop)]
pub struct UploadKey([u8; KEY_BYTES]);

impl UploadKey {
    pub fn generate() -> Self {
        let mut bytes = [0_u8; KEY_BYTES];
        rand::rngs::OsRng.fill_bytes(&mut bytes);
        Self(bytes)
    }

    pub fn from_bytes(bytes: [u8; KEY_BYTES]) -> Self {
        Self(bytes)
    }

    pub fn from_base64(value: &str) -> Result<Self, ProtocolError> {
        let text = value.trim();
        let decoded = STANDARD
            .decode(text)
            .or_else(|_| URL_SAFE_NO_PAD.decode(text))
            .map_err(|_| ProtocolError::InvalidBase64)?;
        let bytes: [u8; KEY_BYTES] = decoded.try_into().map_err(|_| ProtocolError::InvalidKey)?;
        Ok(Self(bytes))
    }

    pub fn to_base64(&self) -> String {
        STANDARD.encode(self.0)
    }

    pub fn key_id(&self) -> String {
        let digest = Sha256::digest(self.0);
        URL_SAFE_NO_PAD.encode(&digest[..8])
    }

    pub fn derive_session(
        &self,
        server_instance_id: [u8; ID_BYTES],
        epoch_id: [u8; ID_BYTES],
    ) -> Result<SessionKeys, ProtocolError> {
        let mut salt = [0_u8; ID_BYTES * 2];
        salt[..ID_BYTES].copy_from_slice(&server_instance_id);
        salt[ID_BYTES..].copy_from_slice(&epoch_id);
        let hkdf = Hkdf::<Sha256>::new(Some(&salt), &self.0);
        let mut c2s = [0_u8; KEY_BYTES];
        let mut s2c = [0_u8; KEY_BYTES];
        hkdf.expand(C2S_INFO, &mut c2s)
            .map_err(|_| ProtocolError::KdfFailed)?;
        hkdf.expand(S2C_INFO, &mut s2c)
            .map_err(|_| ProtocolError::KdfFailed)?;
        Ok(SessionKeys { c2s, s2c })
    }
}

impl fmt::Debug for UploadKey {
    fn fmt(&self, formatter: &mut fmt::Formatter<'_>) -> fmt::Result {
        formatter
            .debug_struct("UploadKey")
            .field("key_id", &self.key_id())
            .finish_non_exhaustive()
    }
}

#[derive(Clone, Zeroize, ZeroizeOnDrop)]
pub struct SessionKeys {
    c2s: [u8; KEY_BYTES],
    s2c: [u8; KEY_BYTES],
}

impl SessionKeys {
    fn key(&self, direction: Direction) -> &[u8; KEY_BYTES] {
        match direction {
            Direction::ClientToServer => &self.c2s,
            Direction::ServerToClient => &self.s2c,
        }
    }
}

impl fmt::Debug for SessionKeys {
    fn fmt(&self, formatter: &mut fmt::Formatter<'_>) -> fmt::Result {
        formatter.write_str("SessionKeys([REDACTED])")
    }
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Direction {
    ClientToServer,
    ServerToClient,
}

impl Direction {
    fn domain(self) -> u32 {
        match self {
            Self::ClientToServer => C2S_DOMAIN,
            Self::ServerToClient => S2C_DOMAIN,
        }
    }
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
pub struct ChallengeRequest {
    pub key_id: String,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
pub struct ChallengeResponse {
    pub protocol: u8,
    pub server_instance_id: String,
    pub epoch_id: String,
    pub expires_at: u64,
}

impl ChallengeResponse {
    pub fn new(
        server_instance_id: [u8; ID_BYTES],
        epoch_id: [u8; ID_BYTES],
        expires_at: u64,
    ) -> Self {
        Self {
            protocol: PROTOCOL_VERSION,
            server_instance_id: URL_SAFE_NO_PAD.encode(server_instance_id),
            epoch_id: URL_SAFE_NO_PAD.encode(epoch_id),
            expires_at,
        }
    }

    pub fn ids(&self) -> Result<([u8; ID_BYTES], [u8; ID_BYTES]), ProtocolError> {
        if self.protocol != PROTOCOL_VERSION {
            return Err(ProtocolError::InvalidMessage("unsupported protocol"));
        }
        Ok((
            decode_id(&self.server_instance_id)?,
            decode_id(&self.epoch_id)?,
        ))
    }
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub enum ClientMessage {
    Probe,
    OpenOrResume {
        device_id: String,
        client_stream_id: String,
        sample_rate: u32,
        channels: u16,
        sample_format: String,
        source_start_sample: u64,
    },
    Pcm {
        server_stream_id: String,
        start_sample: u64,
        samples: Vec<i16>,
    },
    Close {
        server_stream_id: String,
        final_sample: u64,
    },
    MarkIncomplete {
        server_stream_id: String,
    },
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
#[repr(u8)]
pub enum ResponseStatus {
    Ok = 0,
    Gap = 1,
    Incomplete = 2,
    Rejected = 3,
}

impl TryFrom<u8> for ResponseStatus {
    type Error = ProtocolError;

    fn try_from(value: u8) -> Result<Self, Self::Error> {
        match value {
            0 => Ok(Self::Ok),
            1 => Ok(Self::Gap),
            2 => Ok(Self::Incomplete),
            3 => Ok(Self::Rejected),
            _ => Err(ProtocolError::InvalidMessage("unknown response status")),
        }
    }
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct ServerResponse {
    pub status: ResponseStatus,
    pub server_stream_id: String,
    pub next_sample: u64,
    pub accepted_sample_count: u64,
    pub error_code: String,
}

impl ServerResponse {
    pub fn ok(server_stream_id: String, next_sample: u64, accepted: u64) -> Self {
        Self {
            status: ResponseStatus::Ok,
            server_stream_id,
            next_sample,
            accepted_sample_count: accepted,
            error_code: String::new(),
        }
    }

    pub fn rejected(error_code: impl Into<String>) -> Self {
        Self {
            status: ResponseStatus::Rejected,
            server_stream_id: String::new(),
            next_sample: 0,
            accepted_sample_count: 0,
            error_code: error_code.into(),
        }
    }
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct EnvelopeHeader {
    pub key_id: String,
    pub epoch_id: [u8; ID_BYTES],
    pub sequence: u64,
    pub ciphertext_length: u32,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct ParsedEnvelope<'a> {
    pub header: EnvelopeHeader,
    pub aad: &'a [u8],
    pub ciphertext: &'a [u8],
}

pub fn seal_client_message(
    keys: &SessionKeys,
    key_id: &str,
    epoch_id: [u8; ID_BYTES],
    sequence: u64,
    message: &ClientMessage,
) -> Result<Vec<u8>, ProtocolError> {
    seal(
        keys,
        Direction::ClientToServer,
        key_id,
        epoch_id,
        sequence,
        &encode_client_message(message)?,
    )
}

pub fn open_client_message(
    keys: &SessionKeys,
    envelope: &[u8],
) -> Result<(EnvelopeHeader, ClientMessage), ProtocolError> {
    let (header, mut plaintext) = open(keys, Direction::ClientToServer, envelope)?;
    let message = decode_client_message(&plaintext);
    plaintext.fill(0);
    Ok((header, message?))
}

pub fn seal_server_response(
    keys: &SessionKeys,
    key_id: &str,
    epoch_id: [u8; ID_BYTES],
    sequence: u64,
    response: &ServerResponse,
) -> Result<Vec<u8>, ProtocolError> {
    seal(
        keys,
        Direction::ServerToClient,
        key_id,
        epoch_id,
        sequence,
        &encode_server_response(response)?,
    )
}

pub fn open_server_response(
    keys: &SessionKeys,
    envelope: &[u8],
) -> Result<(EnvelopeHeader, ServerResponse), ProtocolError> {
    let (header, mut plaintext) = open(keys, Direction::ServerToClient, envelope)?;
    let response = decode_server_response(&plaintext);
    plaintext.fill(0);
    Ok((header, response?))
}

pub fn parse_envelope(envelope: &[u8]) -> Result<ParsedEnvelope<'_>, ProtocolError> {
    const FIXED: usize = 4 + 1 + 1 + ID_BYTES + 8 + 4;
    if envelope.len() < FIXED + AEAD_TAG_BYTES {
        return Err(ProtocolError::InvalidEnvelope("too short"));
    }
    if envelope[..4] != ENVELOPE_MAGIC {
        return Err(ProtocolError::InvalidEnvelope("bad magic"));
    }
    if envelope[4] != PROTOCOL_VERSION {
        return Err(ProtocolError::InvalidEnvelope("unsupported version"));
    }
    let key_id_len = envelope[5] as usize;
    if key_id_len == 0 || key_id_len > MAX_KEY_ID_BYTES {
        return Err(ProtocolError::InvalidEnvelope("invalid key id length"));
    }
    let header_len = FIXED
        .checked_add(key_id_len)
        .ok_or(ProtocolError::InvalidEnvelope("header overflow"))?;
    if envelope.len() < header_len + AEAD_TAG_BYTES {
        return Err(ProtocolError::InvalidEnvelope("truncated header"));
    }
    let mut epoch_id = [0_u8; ID_BYTES];
    epoch_id.copy_from_slice(&envelope[6..6 + ID_BYTES]);
    let sequence_offset = 6 + ID_BYTES;
    let sequence = u64::from_be_bytes(
        envelope[sequence_offset..sequence_offset + 8]
            .try_into()
            .expect("fixed sequence length"),
    );
    let length_offset = sequence_offset + 8;
    let ciphertext_length = u32::from_be_bytes(
        envelope[length_offset..length_offset + 4]
            .try_into()
            .expect("fixed ciphertext length"),
    );
    if ciphertext_length as usize != envelope.len() - header_len {
        return Err(ProtocolError::InvalidEnvelope("ciphertext length mismatch"));
    }
    let key_id = std::str::from_utf8(&envelope[FIXED..header_len])
        .map_err(|_| ProtocolError::Utf8)?
        .to_owned();
    Ok(ParsedEnvelope {
        header: EnvelopeHeader {
            key_id,
            epoch_id,
            sequence,
            ciphertext_length,
        },
        aad: &envelope[..header_len],
        ciphertext: &envelope[header_len..],
    })
}

fn seal(
    keys: &SessionKeys,
    direction: Direction,
    key_id: &str,
    epoch_id: [u8; ID_BYTES],
    sequence: u64,
    plaintext: &[u8],
) -> Result<Vec<u8>, ProtocolError> {
    let key_id_bytes = key_id.as_bytes();
    if key_id_bytes.is_empty() || key_id_bytes.len() > MAX_KEY_ID_BYTES {
        return Err(ProtocolError::InvalidEnvelope("invalid key id"));
    }
    let ciphertext_length = plaintext
        .len()
        .checked_add(AEAD_TAG_BYTES)
        .and_then(|length| u32::try_from(length).ok())
        .ok_or(ProtocolError::LimitExceeded("ciphertext"))?;
    let mut header = Vec::with_capacity(34 + key_id_bytes.len());
    header.extend_from_slice(&ENVELOPE_MAGIC);
    header.push(PROTOCOL_VERSION);
    header.push(key_id_bytes.len() as u8);
    header.extend_from_slice(&epoch_id);
    header.extend_from_slice(&sequence.to_be_bytes());
    header.extend_from_slice(&ciphertext_length.to_be_bytes());
    header.extend_from_slice(key_id_bytes);

    let cipher = ChaCha20Poly1305::new(Key::from_slice(keys.key(direction)));
    let nonce_bytes = nonce_bytes(direction, sequence);
    let ciphertext = cipher
        .encrypt(
            Nonce::from_slice(&nonce_bytes),
            Payload {
                msg: plaintext,
                aad: &header,
            },
        )
        .map_err(|_| ProtocolError::AuthenticationFailed)?;
    header.extend_from_slice(&ciphertext);
    Ok(header)
}

fn open(
    keys: &SessionKeys,
    direction: Direction,
    envelope: &[u8],
) -> Result<(EnvelopeHeader, Vec<u8>), ProtocolError> {
    let parsed = parse_envelope(envelope)?;
    let cipher = ChaCha20Poly1305::new(Key::from_slice(keys.key(direction)));
    let nonce_bytes = nonce_bytes(direction, parsed.header.sequence);
    let plaintext = cipher
        .decrypt(
            Nonce::from_slice(&nonce_bytes),
            Payload {
                msg: parsed.ciphertext,
                aad: parsed.aad,
            },
        )
        .map_err(|_| ProtocolError::AuthenticationFailed)?;
    Ok((parsed.header, plaintext))
}

fn nonce_bytes(direction: Direction, sequence: u64) -> [u8; 12] {
    let mut nonce = [0_u8; 12];
    nonce[..4].copy_from_slice(&direction.domain().to_be_bytes());
    nonce[4..].copy_from_slice(&sequence.to_be_bytes());
    nonce
}

fn encode_client_message(message: &ClientMessage) -> Result<Vec<u8>, ProtocolError> {
    let mut output = Vec::new();
    match message {
        ClientMessage::Probe => output.push(0),
        ClientMessage::OpenOrResume {
            device_id,
            client_stream_id,
            sample_rate,
            channels,
            sample_format,
            source_start_sample,
        } => {
            output.push(1);
            put_string(&mut output, device_id)?;
            put_string(&mut output, client_stream_id)?;
            output.extend_from_slice(&sample_rate.to_be_bytes());
            output.extend_from_slice(&channels.to_be_bytes());
            put_string(&mut output, sample_format)?;
            output.extend_from_slice(&source_start_sample.to_be_bytes());
        }
        ClientMessage::Pcm {
            server_stream_id,
            start_sample,
            samples,
        } => {
            if samples.is_empty() || samples.len() > MAX_PCM_SAMPLES {
                return Err(ProtocolError::LimitExceeded("pcm samples"));
            }
            output.push(2);
            put_string(&mut output, server_stream_id)?;
            output.extend_from_slice(&start_sample.to_be_bytes());
            output.extend_from_slice(&(samples.len() as u32).to_be_bytes());
            for sample in samples {
                output.extend_from_slice(&sample.to_le_bytes());
            }
        }
        ClientMessage::Close {
            server_stream_id,
            final_sample,
        } => {
            output.push(3);
            put_string(&mut output, server_stream_id)?;
            output.extend_from_slice(&final_sample.to_be_bytes());
        }
        ClientMessage::MarkIncomplete { server_stream_id } => {
            output.push(4);
            put_string(&mut output, server_stream_id)?;
        }
    }
    Ok(output)
}

fn decode_client_message(input: &[u8]) -> Result<ClientMessage, ProtocolError> {
    let mut reader = BinaryReader::new(input);
    match reader.u8()? {
        0 => {
            reader.finish()?;
            Ok(ClientMessage::Probe)
        }
        1 => {
            let message = ClientMessage::OpenOrResume {
                device_id: reader.string()?,
                client_stream_id: reader.string()?,
                sample_rate: reader.u32()?,
                channels: reader.u16()?,
                sample_format: {
                    let sample_format = reader.string()?;
                    if sample_format != SAMPLE_FORMAT_PCM_S16LE {
                        return Err(ProtocolError::InvalidMessage("unsupported sample format"));
                    }
                    sample_format
                },
                source_start_sample: reader.u64()?,
            };
            reader.finish()?;
            Ok(message)
        }
        2 => {
            let server_stream_id = reader.string()?;
            let start_sample = reader.u64()?;
            let sample_count = reader.u32()? as usize;
            if sample_count == 0 || sample_count > MAX_PCM_SAMPLES {
                return Err(ProtocolError::LimitExceeded("pcm samples"));
            }
            let pcm = reader.bytes(
                sample_count
                    .checked_mul(2)
                    .ok_or(ProtocolError::LimitExceeded("pcm bytes"))?,
            )?;
            let samples = pcm
                .chunks_exact(2)
                .map(|pair| i16::from_le_bytes([pair[0], pair[1]]))
                .collect();
            reader.finish()?;
            Ok(ClientMessage::Pcm {
                server_stream_id,
                start_sample,
                samples,
            })
        }
        3 => {
            let message = ClientMessage::Close {
                server_stream_id: reader.string()?,
                final_sample: reader.u64()?,
            };
            reader.finish()?;
            Ok(message)
        }
        4 => {
            let message = ClientMessage::MarkIncomplete {
                server_stream_id: reader.string()?,
            };
            reader.finish()?;
            Ok(message)
        }
        _ => Err(ProtocolError::InvalidMessage("unknown client message")),
    }
}

fn encode_server_response(response: &ServerResponse) -> Result<Vec<u8>, ProtocolError> {
    let mut output = Vec::new();
    output.push(response.status as u8);
    put_string(&mut output, &response.server_stream_id)?;
    output.extend_from_slice(&response.next_sample.to_be_bytes());
    output.extend_from_slice(&response.accepted_sample_count.to_be_bytes());
    put_string(&mut output, &response.error_code)?;
    Ok(output)
}

fn decode_server_response(input: &[u8]) -> Result<ServerResponse, ProtocolError> {
    let mut reader = BinaryReader::new(input);
    let response = ServerResponse {
        status: ResponseStatus::try_from(reader.u8()?)?,
        server_stream_id: reader.string()?,
        next_sample: reader.u64()?,
        accepted_sample_count: reader.u64()?,
        error_code: reader.string()?,
    };
    reader.finish()?;
    Ok(response)
}

fn put_string(output: &mut Vec<u8>, value: &str) -> Result<(), ProtocolError> {
    let bytes = value.as_bytes();
    if bytes.len() > MAX_STRING_BYTES || bytes.len() > u16::MAX as usize {
        return Err(ProtocolError::LimitExceeded("string"));
    }
    output.extend_from_slice(&(bytes.len() as u16).to_be_bytes());
    output.extend_from_slice(bytes);
    Ok(())
}

fn decode_id(value: &str) -> Result<[u8; ID_BYTES], ProtocolError> {
    let decoded = URL_SAFE_NO_PAD
        .decode(value)
        .map_err(|_| ProtocolError::InvalidBase64)?;
    decoded
        .try_into()
        .map_err(|_| ProtocolError::InvalidMessage("invalid id length"))
}

struct BinaryReader<'a> {
    input: &'a [u8],
    offset: usize,
}

impl<'a> BinaryReader<'a> {
    fn new(input: &'a [u8]) -> Self {
        Self { input, offset: 0 }
    }

    fn bytes(&mut self, count: usize) -> Result<&'a [u8], ProtocolError> {
        let end = self
            .offset
            .checked_add(count)
            .ok_or(ProtocolError::InvalidMessage("length overflow"))?;
        let value = self
            .input
            .get(self.offset..end)
            .ok_or(ProtocolError::InvalidMessage("truncated"))?;
        self.offset = end;
        Ok(value)
    }

    fn u8(&mut self) -> Result<u8, ProtocolError> {
        Ok(self.bytes(1)?[0])
    }

    fn u16(&mut self) -> Result<u16, ProtocolError> {
        Ok(u16::from_be_bytes(
            self.bytes(2)?.try_into().expect("fixed u16 length"),
        ))
    }

    fn u32(&mut self) -> Result<u32, ProtocolError> {
        Ok(u32::from_be_bytes(
            self.bytes(4)?.try_into().expect("fixed u32 length"),
        ))
    }

    fn u64(&mut self) -> Result<u64, ProtocolError> {
        Ok(u64::from_be_bytes(
            self.bytes(8)?.try_into().expect("fixed u64 length"),
        ))
    }

    fn string(&mut self) -> Result<String, ProtocolError> {
        let length = self.u16()? as usize;
        if length > MAX_STRING_BYTES {
            return Err(ProtocolError::LimitExceeded("string"));
        }
        std::str::from_utf8(self.bytes(length)?)
            .map(str::to_owned)
            .map_err(|_| ProtocolError::Utf8)
    }

    fn finish(&self) -> Result<(), ProtocolError> {
        if self.offset == self.input.len() {
            Ok(())
        } else {
            Err(ProtocolError::InvalidMessage("trailing bytes"))
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn fixture() -> (UploadKey, [u8; ID_BYTES], [u8; ID_BYTES], SessionKeys) {
        let key = UploadKey::from_bytes([7; KEY_BYTES]);
        let server = [8; ID_BYTES];
        let epoch = [9; ID_BYTES];
        let keys = key.derive_session(server, epoch).unwrap();
        (key, server, epoch, keys)
    }

    #[test]
    fn client_pcm_round_trips_and_retry_is_byte_identical() {
        let (key, _, epoch, keys) = fixture();
        let message = ClientMessage::Pcm {
            server_stream_id: "stream-1".to_string(),
            start_sample: 42,
            samples: vec![-32768, -1, 0, 1, 32767],
        };
        let first = seal_client_message(&keys, &key.key_id(), epoch, 4, &message).unwrap();
        let retry = seal_client_message(&keys, &key.key_id(), epoch, 4, &message).unwrap();
        assert_eq!(first, retry);
        let (header, decoded) = open_client_message(&keys, &first).unwrap();
        assert_eq!(header.sequence, 4);
        assert_eq!(decoded, message);
    }

    #[test]
    fn any_authenticated_change_is_rejected() {
        let (key, _, epoch, keys) = fixture();
        let message = ClientMessage::Close {
            server_stream_id: "stream-1".to_string(),
            final_sample: 99,
        };
        let envelope = seal_client_message(&keys, &key.key_id(), epoch, 1, &message).unwrap();
        for index in [4_usize, 10, envelope.len() - 1] {
            let mut tampered = envelope.clone();
            tampered[index] ^= 1;
            assert!(open_client_message(&keys, &tampered).is_err());
        }
    }

    #[test]
    fn direction_keys_are_separate() {
        let (key, _, epoch, keys) = fixture();
        let response = ServerResponse::ok("server-stream".to_string(), 10, 10);
        let envelope = seal_server_response(&keys, &key.key_id(), epoch, 0, &response).unwrap();
        assert_eq!(open_server_response(&keys, &envelope).unwrap().1, response);
        assert!(open_client_message(&keys, &envelope).is_err());
    }

    #[test]
    fn mark_incomplete_round_trips() {
        let (key, _, epoch, keys) = fixture();
        let message = ClientMessage::MarkIncomplete {
            server_stream_id: "stream-1".to_string(),
        };
        let envelope = seal_client_message(&keys, &key.key_id(), epoch, 2, &message).unwrap();
        let (header, decoded) = open_client_message(&keys, &envelope).unwrap();
        assert_eq!(header.sequence, 2);
        assert_eq!(decoded, message);
    }

    #[test]
    fn open_or_resume_round_trips_with_sample_format() {
        let (key, _, epoch, keys) = fixture();
        let message = ClientMessage::OpenOrResume {
            device_id: "device-1".to_string(),
            client_stream_id: "session-1".to_string(),
            sample_rate: 16_000,
            channels: 1,
            sample_format: SAMPLE_FORMAT_PCM_S16LE.to_string(),
            source_start_sample: 7,
        };
        let envelope = seal_client_message(&keys, &key.key_id(), epoch, 0, &message).unwrap();
        let (_, decoded) = open_client_message(&keys, &envelope).unwrap();
        assert_eq!(decoded, message);
    }

    #[test]
    fn authenticated_probe_round_trips() {
        let (key, _, epoch, keys) = fixture();
        let envelope =
            seal_client_message(&keys, &key.key_id(), epoch, 0, &ClientMessage::Probe).unwrap();
        let (_, decoded) = open_client_message(&keys, &envelope).unwrap();
        assert_eq!(decoded, ClientMessage::Probe);
    }

    #[test]
    fn challenge_ids_and_key_base64_round_trip() {
        let (key, server, epoch, _) = fixture();
        let challenge = ChallengeResponse::new(server, epoch, 123);
        assert_eq!(challenge.ids().unwrap(), (server, epoch));
        let decoded = UploadKey::from_base64(&key.to_base64()).unwrap();
        assert_eq!(decoded.key_id(), key.key_id());
    }
}
