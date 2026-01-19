import { BluetoothService, PairedDevice, ReceivedFile } from '../services/BluetoothService';
import { abilityAccessCtrl, common, Permissions } from '@kit.AbilityKit';
import { picker } from '@kit.CoreFileKit';
import { fileIo } from '@kit.CoreFileKit';

@Entry
@Component
struct Index {
  @State isConnected: boolean = false;
  @State isServerRunning: boolean = false;
  @State pairedDevices: PairedDevice[] = [];
  @State selectedDevice: string = '';
  @State logs: string[] = [];
  @State receivedFiles: ReceivedFile[] = [];

  private btService: BluetoothService = BluetoothService.getInstance();

  aboutToAppear(): void {
    this.requestPermissions();
    this.setupCallbacks();
  }

  aboutToDisappear(): void {
    this.btService.destroy();
  }

  private requestPermissions(): void {
    try {
      const context = this.getUIContext().getHostContext() as common.UIAbilityContext;
      const permissions: Permissions[] = [
        'ohos.permission.ACCESS_BLUETOOTH',
        'ohos.permission.LOCATION',
        'ohos.permission.APPROXIMATELY_LOCATION'
      ];
      abilityAccessCtrl.createAtManager().requestPermissionsFromUser(context, permissions);
    } catch (e) {
      this.addLog('权限请求失败');
    }
  }

  private setupCallbacks(): void {
    this.btService.setCallbacks(
      (msg: string) => {
        this.addLog(msg);
        this.isConnected = this.btService.isConnected();
      },
      undefined,
      (file: ReceivedFile) => {
        this.receivedFiles = [file, ...this.receivedFiles];
        this.addLog(`收到文件: ${file.fileName}`);
      }
    );
  }

  private addLog(msg: string): void {
    const time = new Date().toLocaleTimeString();
    this.logs = [`[${time}] ${msg}`, ...this.logs.slice(0, 30)];
  }

  private refreshDevices(): void {
    this.pairedDevices = this.btService.getPairedDevices();
  }

  private toggleServer(): void {
    if (this.isServerRunning) {
      this.btService.stopServer();
      this.isServerRunning = false;
    } else {
      this.btService.startServer();
      this.isServerRunning = true;
    }
  }

  private connectDevice(deviceId: string): void {
    this.btService.connectToDevice(deviceId);
  }

  private disconnect(): void {
    this.btService.disconnect();
    this.isConnected = false;
  }

  private selectAndSendFile(): void {
    try {
      const context = this.getUIContext().getHostContext() as common.UIAbilityContext;
      const documentPicker = new picker.DocumentViewPicker(context);
      documentPicker.select({ maxSelectNumber: 1 }).then((uris: string[]) => {
        if (uris.length > 0) {
          this.sendFileByUri(uris[0]);
        }
      });
    } catch (e) {
      this.addLog('选择文件失败');
    }
  }

  private sendFileByUri(uri: string): void {
    try {
      const file = fileIo.openSync(uri, fileIo.OpenMode.READ_ONLY);
      const stat = fileIo.statSync(file.fd);
      const buffer = new ArrayBuffer(stat.size);
      fileIo.readSync(file.fd, buffer);
      fileIo.closeSync(file);

      const fileName = uri.split('/').pop() || 'file';
      this.btService.sendFile(fileName, buffer);
    } catch (e) {
      this.addLog('读取文件失败');
    }
  }

  private saveReceivedFile(file: ReceivedFile): void {
    try {
      const context = this.getUIContext().getHostContext() as common.UIAbilityContext;
      const documentPicker = new picker.DocumentViewPicker(context);
      documentPicker.save({ newFileNames: [file.fileName] }).then((uris: string[]) => {
        if (uris.length > 0) {
          const f = fileIo.openSync(uris[0], fileIo.OpenMode.WRITE_ONLY | fileIo.OpenMode.CREATE);
          fileIo.writeSync(f.fd, file.data);
          fileIo.closeSync(f);
          this.addLog(`已保存: ${file.fileName}`);
        }
      });
    } catch (e) {
      this.addLog('保存失败');
    }
  }

  build() {
    Column() {
      Text('蓝牙文件传输')
        .fontSize(22)
        .fontWeight(FontWeight.Bold)
        .margin({ top: 16, bottom: 16 })

      // 状态栏
      Row() {
        Text('连接状态: ')
        Text(this.isConnected ? '已连接' : '未连接')
          .fontColor(this.isConnected ? '#00AA00' : '#999')
      }
      .width('90%')
      .margin({ bottom: 12 })

      // 服务端模式
      Row() {
        Button(this.isServerRunning ? '停止服务' : '启动服务(等待连接)')
          .width('100%')
          .height(44)
          .backgroundColor(this.isServerRunning ? '#FF6B6B' : '#4ECDC4')
          .onClick(() => this.toggleServer())
      }
      .width('90%')
      .margin({ bottom: 12 })

      // 分割线
      Divider().width('90%').margin({ top: 8, bottom: 8 })

      // 客户端模式 - 已配对设备列表
      Row() {
        Text('已配对设备')
          .fontSize(16)
        Blank()
        Button('刷新')
          .height(32)
          .fontSize(14)
          .onClick(() => this.refreshDevices())
      }
      .width('90%')
      .margin({ bottom: 8 })

      if (this.pairedDevices.length > 0) {
        List() {
          ForEach(this.pairedDevices, (device: PairedDevice) => {
            ListItem() {
              Row() {
                Column() {
                  Text(device.deviceName)
                    .fontSize(14)
                  Text(device.deviceId)
                    .fontSize(10)
                    .fontColor('#999')
                }
                .alignItems(HorizontalAlign.Start)

                Blank()
                Button('连接')
                  .height(28)
                  .fontSize(12)
                  .onClick(() => this.connectDevice(device.deviceId))
              }
              .width('100%')
              .padding(8)
            }
          })
        }
        .width('90%')
        .height(120)
        .backgroundColor('#F5F5F5')
        .borderRadius(8)
      } else {
        Text('点击刷新获取已配对设备')
          .fontSize(12)
          .fontColor('#999')
          .margin({ top: 8, bottom: 8 })
      }

      // 分割线
      Divider().width('90%').margin({ top: 8, bottom: 8 })

      // 文件操作
      Row() {
        Button('发送文件')
          .width('45%')
          .height(44)
          .backgroundColor(this.isConnected ? '#45B7D1' : '#CCC')
          .enabled(this.isConnected)
          .onClick(() => this.selectAndSendFile())

        Button('断开连接')
          .width('45%')
          .height(44)
          .backgroundColor(this.isConnected ? '#FF6B6B' : '#CCC')
          .enabled(this.isConnected)
          .onClick(() => this.disconnect())
      }
      .width('90%')
      .justifyContent(FlexAlign.SpaceBetween)
      .margin({ bottom: 12 })

      // 收到的文件
      if (this.receivedFiles.length > 0) {
        Text('收到的文件')
          .fontSize(14)
          .width('90%')
          .margin({ bottom: 4 })

        List() {
          ForEach(this.receivedFiles, (file: ReceivedFile, index: number) => {
            ListItem() {
              Row() {
                Text(file.fileName)
                  .fontSize(12)
                Blank()
                Button('保存')
                  .height(24)
                  .fontSize(10)
                  .onClick(() => this.saveReceivedFile(file))
              }
              .width('100%')
              .padding(6)
            }
          })
        }
        .width('90%')
        .height(80)
        .backgroundColor('#E8F5E9')
        .borderRadius(8)
        .margin({ bottom: 8 })
      }

      // 日志
      Text('日志')
        .fontSize(14)
        .width('90%')
        .margin({ top: 8, bottom: 4 })

      Scroll() {
        Column() {
          ForEach(this.logs, (log: string) => {
            Text(log)
              .fontSize(10)
              .width('100%')
              .padding(2)
          })
        }
      }
      .width('90%')
      .height(150)
      .backgroundColor('#F5F5F5')
      .borderRadius(8)
    }
    .width('100%')
    .height('100%')
    .backgroundColor('#FFF')
  }
}
