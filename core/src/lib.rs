use std::net::TcpListener;
use std::io::Write;
use std::sync::Mutex;
use std::thread;
use std::sync::mpsc::{channel, Sender};

static SERVER_SENDER: std::sync::OnceLock<Mutex<Option<Sender<Vec<u8>>>>> = std::sync::OnceLock::new();

fn get_sender() -> &'static Mutex<Option<Sender<Vec<u8>>>> {
    SERVER_SENDER.get_or_init(|| Mutex::new(None))
}

pub fn start_server(port: i32) -> bool {
    let listener = match TcpListener::bind(format!("0.0.0.0:{}", port)) {
        Ok(l) => l,
        Err(_) => return false,
    };
    
    let (tx, rx) = channel::<Vec<u8>>();
    *get_sender().lock().unwrap() = Some(tx);
    
    thread::spawn(move || {
        for stream in listener.incoming() {
            if let Ok(mut stream) = stream {
                let _ = stream.set_nodelay(true);
                while let Ok(msg) = rx.recv() {
                    if stream.write_all(&msg).is_err() {
                        break;
                    }
                }
            }
        }
    });
    true
}

pub fn stop_server() {
    *get_sender().lock().unwrap() = None;
}

pub fn send_config(width: i16, height: i16, fps: i8, rotation: i8, mirror: bool, sps: &[u8], pps: &[u8]) {
    let mut msg = Vec::with_capacity(14 + sps.len() + pps.len());
    msg.push(1);
    msg.extend_from_slice(&width.to_be_bytes());
    msg.extend_from_slice(&height.to_be_bytes());
    msg.push(fps as u8);
    msg.push(rotation as u8);
    msg.push(if mirror { 1 } else { 0 });
    msg.extend_from_slice(&(sps.len() as u16).to_be_bytes());
    msg.extend_from_slice(sps);
    msg.extend_from_slice(&(pps.len() as u16).to_be_bytes());
    msg.extend_from_slice(pps);
    
    if let Some(tx) = get_sender().lock().unwrap().as_ref() {
        let _ = tx.send(msg);
    }
}

pub fn send_frame(frame_type: i8, timestamp: i64, payload: &[u8]) {
    let mut msg = Vec::with_capacity(16 + payload.len());
    msg.extend_from_slice(&[0x4c, 0x55, 1]); // L U 1
    msg.extend_from_slice(&(payload.len() as i32).to_be_bytes());
    msg.push(frame_type as u8);
    msg.extend_from_slice(&timestamp.to_be_bytes());
    msg.extend_from_slice(payload);
    
    if let Some(tx) = get_sender().lock().unwrap().as_ref() {
        let _ = tx.send(msg);
    }
}

#[cfg(target_os = "android")]
#[allow(non_snake_case)]
pub mod android {
    use jni::JNIEnv;
    use jni::objects::{JClass, JByteArray};
    use jni::sys::{jboolean, jint, jlong};
    use super::*;

    #[no_mangle]
    pub extern "system" fn Java_com_example_lumen_LumenEngine_startServer(
        mut _env: JNIEnv, _class: JClass, port: jint
    ) -> jboolean {
        if start_server(port) { 1 } else { 0 }
    }

    #[no_mangle]
    pub extern "system" fn Java_com_example_lumen_LumenEngine_stopServer(
        mut _env: JNIEnv, _class: JClass
    ) {
        stop_server();
    }

    #[no_mangle]
    pub extern "system" fn Java_com_example_lumen_LumenEngine_sendConfig(
        mut env: JNIEnv, _class: JClass,
        width: jint, height: jint, fps: jint, rotation: jint, mirror: jboolean,
        sps: JByteArray, pps: JByteArray
    ) {
        let sps_bytes = env.convert_byte_array(&sps).unwrap_or_default();
        let pps_bytes = env.convert_byte_array(&pps).unwrap_or_default();
        send_config(width as i16, height as i16, fps as i8, rotation as i8, mirror != 0, &sps_bytes, &pps_bytes);
    }

    #[no_mangle]
    pub extern "system" fn Java_com_example_lumen_LumenEngine_sendFrame(
        mut env: JNIEnv, _class: JClass,
        frame_type: jint, timestamp_us: jlong, payload: JByteArray
    ) {
        let payload_bytes = env.convert_byte_array(&payload).unwrap_or_default();
        send_frame(frame_type as i8, timestamp_us, &payload_bytes);
    }
}
