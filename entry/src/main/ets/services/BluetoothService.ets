import { socket, access, connection } from '@kit.ConnectivityKit';
import { BusinessError } from '@kit.BasicServicesKit';

// SPP 标准 UUID
const SPP_UUID = '00001101-0000-1000-8000-00805f9b34fb';

export class PairedDevice {
  deviceId: string = '';
  deviceName: string = '';

  constructor(deviceId: string, deviceName: string) {
    this.deviceId = deviceId;
    this.deviceName = deviceName;
  }
}

export class ReceivedFile {
  fileName: string = '';
  data: ArrayBuffer = new ArrayBuffer(0);

  constructor(fileName: string, data: ArrayBuffer) {
    this.fileName = fileName;
    this.data = data;
  }
}

type StateCallback = (state: string) => void;
type DataCallback = (data: ArrayBuffer) => void;
type FileCallback = (file: ReceivedFile) => void;

export class BluetoothService {
  private static instance: BluetoothService;

  // Socket IDs
  private serverSocketId: number = -1;
  private clientSocketId: number = -1;
  private connectedSocketId: number = -1;

  // 回调
  private onStateChange: StateCallback | null = null;
  private onDataReceived: DataCallback | null = null;
  private onFileReceived: FileCallback | null = null;

  // 文件接收缓冲
  private receiveBuffer: number[] = [];
  private expectedFileSize: number = 0;
  private expectedFileName: string = '';
  private isReceivingFile: boolean = false;

  private constructor() {}

  public static getInstance(): BluetoothService {
    if (!BluetoothService.instance) {
      BluetoothService.instance = new BluetoothService();
    }
    return BluetoothService.instance;
  }

  public setCallbacks(
    onStateChange?: StateCallback,
    onDataReceived?: DataCallback,
    onFileReceived?: FileCallback
  ): void {
    if (onStateChange) this.onStateChange = onStateChange;
    if (onDataReceived) this.onDataReceived = onDataReceived;
    if (onFileReceived) this.onFileReceived = onFileReceived;
  }

  private log(msg: string): void {
    console.info('BT', msg);
    if (this.onStateChange) {
      this.onStateChange(msg);
    }
  }

  // ==================== 蓝牙状态 ====================

  public isBluetoothOn(): boolean {
    try {
      const state = access.getState();
      return state === access.BluetoothState.STATE_ON;
    } catch (err) {
      return false;
    }
  }

  public enableBluetooth(): void {
    try {
      access.enableBluetooth();
      this.log('正在开启蓝牙...');
    } catch (err) {
      this.log('开启蓝牙失败');
    }
  }

  // ==================== 获取已配对设备 ====================

  public getPairedDevices(): PairedDevice[] {
    try {
      const devices = connection.getPairedDevices();
      const result: PairedDevice[] = [];
      for (const deviceId of devices) {
        let deviceName = deviceId;
        try {
          deviceName = connection.getRemoteDeviceName(deviceId);
        } catch (e) {
          // 获取名称失败，用地址代替
        }
        result.push(new PairedDevice(deviceId, deviceName));
      }
      this.log(`找到 ${result.length} 个已配对设备`);
      return result;
    } catch (err) {
      this.log('获取配对设备失败');
      return [];
    }
  }

  // ==================== SPP 服务端（等待连接）====================

  public startServer(): void {
    if (this.serverSocketId >= 0) {
      this.log('服务已在运行');
      return;
    }

    try {
      const options: socket.SppOptions = {
        uuid: SPP_UUID,
        secure: true,
        type: socket.SppType.SPP_RFCOMM
      };

      socket.sppListen('FileTransfer', options, (err: BusinessError, serverId: number) => {
        if (err) {
          this.log('启动服务失败: ' + err.code);
          return;
        }
        this.serverSocketId = serverId;
        this.log('服务已启动，等待连接...');
        this.acceptConnection();
      });
    } catch (err) {
      this.log('启动服务异常');
    }
  }

  private acceptConnection(): void {
    if (this.serverSocketId < 0) return;

    socket.sppAccept(this.serverSocketId, (err: BusinessError, clientId: number) => {
      if (err) {
        this.log('接受连接失败: ' + err.code);
        return;
      }
      this.connectedSocketId = clientId;
      this.log('设备已连接');
      this.startDataListener(clientId);
      // 继续监听新连接
      this.acceptConnection();
    });
  }

  public stopServer(): void {
    try {
      if (this.connectedSocketId >= 0) {
        socket.sppCloseClientSocket(this.connectedSocketId);
        this.connectedSocketId = -1;
      }
      if (this.serverSocketId >= 0) {
        socket.sppCloseServerSocket(this.serverSocketId);
        this.serverSocketId = -1;
      }
      this.log('服务已停止');
    } catch (err) {
      this.log('停止服务异常');
    }
  }

  // ==================== SPP 客户端（主动连接）====================

  public connectToDevice(deviceId: string): void {
    if (this.clientSocketId >= 0) {
      this.log('已有连接');
      return;
    }

    try {
      const options: socket.SppOptions = {
        uuid: SPP_UUID,
        secure: true,
        type: socket.SppType.SPP_RFCOMM
      };

      this.log('正在连接 ' + deviceId + '...');

      socket.sppConnect(deviceId, options, (err: BusinessError, socketId: number) => {
        if (err) {
          this.log('连接失败: ' + err.code);
          return;
        }
        this.clientSocketId = socketId;
        this.connectedSocketId = socketId;
        this.log('连接成功');
        this.startDataListener(socketId);
      });
    } catch (err) {
      this.log('连接异常');
    }
  }

  public disconnect(): void {
    try {
      if (this.clientSocketId >= 0) {
        socket.sppCloseClientSocket(this.clientSocketId);
        this.clientSocketId = -1;
        this.connectedSocketId = -1;
        this.log('已断开连接');
      }
    } catch (err) {
      this.log('断开异常');
    }
  }

  // ==================== 数据收发 ====================

  private startDataListener(socketId: number): void {
    try {
      socket.on('sppRead', socketId, (data: ArrayBuffer) => {
        this.handleReceivedData(data);
      });
    } catch (err) {
      this.log('监听数据异常');
    }
  }

  private handleReceivedData(data: ArrayBuffer): void {
    const bytes = new Uint8Array(data);

    // 检查是否是文件头 (magic: 0x46 0x49 0x4C 0x45 = "FILE")
    if (!this.isReceivingFile && bytes.length >= 12 &&
        bytes[0] === 0x46 && bytes[1] === 0x49 && bytes[2] === 0x4C && bytes[3] === 0x45) {
      // 解析文件头
      const view = new DataView(data);
      const nameLen = view.getUint32(4, true);
      this.expectedFileSize = view.getUint32(8, true);

      const nameBytes = bytes.slice(12, 12 + nameLen);
      this.expectedFileName = this.utf8BytesToString(nameBytes);

      this.isReceivingFile = true;
      this.receiveBuffer = [];
      this.log(`接收文件: ${this.expectedFileName} (${this.expectedFileSize} 字节)`);

      // 如果头部后面还有数据，追加到缓冲
      if (bytes.length > 12 + nameLen) {
        const remaining = bytes.slice(12 + nameLen);
        for (let i = 0; i < remaining.length; i++) {
          this.receiveBuffer.push(remaining[i]);
        }
      }
    } else if (this.isReceivingFile) {
      // 追加数据
      for (let i = 0; i < bytes.length; i++) {
        this.receiveBuffer.push(bytes[i]);
      }
    }

    // 检查是否接收完成
    if (this.isReceivingFile && this.receiveBuffer.length >= this.expectedFileSize) {
      const fileData: ArrayBuffer = new ArrayBuffer(this.expectedFileSize);
      const fileView: Uint8Array = new Uint8Array(fileData);
      for (let i = 0; i < this.expectedFileSize; i++) {
        fileView[i] = this.receiveBuffer[i];
      }
      this.log(`文件接收完成: ${this.expectedFileName}`);

      if (this.onFileReceived) {
        const receivedFile: ReceivedFile = new ReceivedFile(this.expectedFileName, fileData);
        this.onFileReceived(receivedFile);
      }

      this.isReceivingFile = false;
      this.receiveBuffer = [];
    }
  }

  // 发送文件
  public sendFile(fileName: string, data: ArrayBuffer): void {
    if (this.connectedSocketId < 0) {
      this.log('未连接，无法发送');
      return;
    }

    try {
      // 构造文件头
      const nameBytes = this.stringToUtf8Bytes(fileName);
      const header = new ArrayBuffer(12 + nameBytes.length);
      const headerView = new DataView(header);
      const headerArray = new Uint8Array(header);

      // Magic: "FILE"
      headerArray[0] = 0x46;
      headerArray[1] = 0x49;
      headerArray[2] = 0x4C;
      headerArray[3] = 0x45;
      // 文件名长度
      headerView.setUint32(4, nameBytes.length, true);
      // 文件大小
      headerView.setUint32(8, data.byteLength, true);
      // 文件名
      for (let i = 0; i < nameBytes.length; i++) {
        headerArray[12 + i] = nameBytes[i];
      }

      // 发送头部
      socket.sppWrite(this.connectedSocketId, header);
      this.log(`发送文件: ${fileName} (${data.byteLength} 字节)`);

      // 分块发送数据
      const CHUNK_SIZE = 990; // SPP 推荐块大小
      const fileBytes = new Uint8Array(data);
      let sent = 0;

      while (sent < fileBytes.length) {
        const end = Math.min(sent + CHUNK_SIZE, fileBytes.length);
        const chunk = fileBytes.slice(sent, end);
        socket.sppWrite(this.connectedSocketId, chunk.buffer as ArrayBuffer);
        sent = end;
      }

      this.log('文件发送完成');
    } catch (err) {
      this.log('发送失败');
    }
  }

  // ==================== 工具函数 ====================

  private stringToUtf8Bytes(str: string): Uint8Array {
    const bytes: number[] = [];
    for (let i = 0; i < str.length; i++) {
      const code = str.charCodeAt(i);
      if (code < 0x80) {
        bytes.push(code);
      } else if (code < 0x800) {
        bytes.push(0xc0 | (code >> 6));
        bytes.push(0x80 | (code & 0x3f));
      } else {
        bytes.push(0xe0 | (code >> 12));
        bytes.push(0x80 | ((code >> 6) & 0x3f));
        bytes.push(0x80 | (code & 0x3f));
      }
    }
    return new Uint8Array(bytes);
  }

  private utf8BytesToString(bytes: Uint8Array): string {
    let str = '';
    let i = 0;
    while (i < bytes.length) {
      const b = bytes[i];
      if (b < 0x80) {
        str += String.fromCharCode(b);
        i++;
      } else if ((b & 0xe0) === 0xc0) {
        str += String.fromCharCode(((b & 0x1f) << 6) | (bytes[i + 1] & 0x3f));
        i += 2;
      } else {
        str += String.fromCharCode(((b & 0x0f) << 12) | ((bytes[i + 1] & 0x3f) << 6) | (bytes[i + 2] & 0x3f));
        i += 3;
      }
    }
    return str;
  }

  public isConnected(): boolean {
    return this.connectedSocketId >= 0;
  }

  public destroy(): void {
    this.disconnect();
    this.stopServer();
  }
}
