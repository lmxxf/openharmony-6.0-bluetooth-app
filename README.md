# OpenHarmony 6.0 蓝牙文件传输 App

## 项目目标

在 OpenHarmony 6.0 设备和手机之间通过蓝牙传输文件（双向）。

## 开发环境

- DevEco Studio
- OpenHarmony 6.0 SDK
- ArkTS 语言

## 开发过程记录

### 1. 初始需求

用户需要在已配对的蓝牙设备之间传输文件，支持：
- OpenHarmony → 手机
- 手机 → OpenHarmony

### 2. 技术方案选择

#### 方案 A：BLE（低功耗蓝牙）- 已放弃
- 尝试使用 `@kit.ConnectivityKit` 的 `ble` 模块
- 问题：BLE 适合小数据量传输，MTU 限制大文件传输效率低
- 问题：OpenHarmony 6.0 的 BLE API 变化大，文档不完善

#### 方案 B：SPP（蓝牙串口协议）- 当前方案
- 使用 `@kit.ConnectivityKit` 的 `socket` 模块
- SPP 适合文件传输，带宽更高
- 支持服务端/客户端双模式

### 3. 遇到的问题及解决

#### 3.1 权限问题

**错误**：
```
Install Failed: error: install failed due to grant request permissions failed.
PermissionName: ohos.permission.MANAGE_BLUETOOTH
```

**原因**：`MANAGE_BLUETOOTH` 是系统权限，普通应用无法申请

**解决**：移除系统级权限，只保留：
```json
"requestPermissions": [
  { "name": "ohos.permission.ACCESS_BLUETOOTH" },
  { "name": "ohos.permission.LOCATION" },
  { "name": "ohos.permission.APPROXIMATELY_LOCATION" }
]
```

已废弃的权限（不需要）：
- `ohos.permission.DISCOVER_BLUETOOTH`
- `ohos.permission.USE_BLUETOOTH`
- `ohos.permission.MANAGE_BLUETOOTH`

#### 3.2 ArkTS 语法限制

**错误 1**：`arkts-limited-throw`
```
"throw" statements cannot accept values of arbitrary types
```
**解决**：不使用 `throw err`，改用 `console.error` 记录错误

**错误 2**：`arkts-no-any-unknown`
```
Use explicit types instead of "any", "unknown"
```
**解决**：所有变量必须声明明确类型

**错误 3**：`arkts-no-untyped-obj-literals`
```
Object literal must correspond to some explicitly declared class or interface
```
**解决**：不能使用匿名对象字面量，必须用 class 定义：
```typescript
// 错误写法
const obj = { name: "test", value: 123 };

// 正确写法
class MyClass {
  name: string = '';
  value: number = 0;
  constructor(name: string, value: number) {
    this.name = name;
    this.value = value;
  }
}
const obj = new MyClass("test", 123);
```

**错误 4**：`arkts-no-structural-typing`
```
Structural typing is not supported
```
**解决**：`Uint8Array.buffer` 返回 `ArrayBufferLike`，需要显式转换为 `ArrayBuffer`：
```typescript
// 错误写法
const data = uint8Array.buffer;

// 正确写法
const data = new ArrayBuffer(uint8Array.length);
new Uint8Array(data).set(uint8Array);
```

#### 3.3 API 废弃问题

**警告**：`'getContext' has been deprecated`

**解决**：使用新 API
```typescript
// 旧写法
const context = getContext(this);

// 新写法
const context = this.getUIContext().getHostContext();
```

**警告**：`'showToast' has been deprecated`

**解决**：自定义 Toast 组件替代 `promptAction.showToast`

#### 3.4 TextEncoder 问题

OpenHarmony 的 `util.TextEncoder` API 与标准不同：
- `encodeInto()` 返回类型不是标准的 `Uint8Array`
- `encodeIntoUint8Array()` 需要两个参数

**解决**：手写 UTF-8 编码函数：
```typescript
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
```

### 4. 当前代码结构

```
entry/src/main/
├── ets/
│   ├── entryability/
│   │   └── EntryAbility.ets      # 应用入口，设置屏幕常亮
│   ├── pages/
│   │   └── Index.ets             # 主界面
│   └── services/
│       └── BluetoothService.ets  # 蓝牙服务（SPP）
├── resources/
│   └── base/element/string.json  # 字符串资源
└── module.json5                  # 模块配置、权限声明
```

### 5. 功能设计

#### BluetoothService 类
- `startServer()` - 启动 SPP 服务端，等待连接
- `stopServer()` - 停止服务
- `connectToDevice(deviceId)` - 作为客户端连接已配对设备
- `disconnect()` - 断开连接
- `getPairedDevices()` - 获取已配对设备列表
- `sendFile(fileName, data)` - 发送文件
- 接收文件通过回调 `onFileReceived`

#### 文件传输协议
自定义简单协议：
```
文件头 (12 + N 字节):
  [0-3]   Magic: "FILE" (0x46 0x49 0x4C 0x45)
  [4-7]   文件名长度 (uint32, little-endian)
  [8-11]  文件大小 (uint32, little-endian)
  [12-N]  文件名 (UTF-8)

文件数据:
  分块发送，每块 990 字节
```

### 6. 待开发：Android 端配套 App

当前 OpenHarmony 端已完成，但需要 Android 端配套 App 才能实现文件传输。

#### 问题
- 系统自带的蓝牙文件分享使用 **OBEX/OPP 协议**，与 SPP 不兼容
- 需要一个 Android App 作为 SPP 客户端

#### Android App 需求
- 语言：Kotlin
- 最低 SDK：Android 6.0 (API 23)
- 目标设备：一加 13 (Android 15)

#### Android App 功能设计
1. **蓝牙权限申请**
   - `BLUETOOTH_CONNECT`
   - `BLUETOOTH_SCAN`（如需扫描）

2. **获取已配对设备列表**
   ```kotlin
   val pairedDevices = bluetoothAdapter.bondedDevices
   ```

3. **SPP 连接**
   ```kotlin
   val uuid = UUID.fromString("00001101-0000-1000-8000-00805f9b34fb")
   val socket = device.createRfcommSocketToServiceRecord(uuid)
   socket.connect()
   ```

4. **文件传输协议**（与 OpenHarmony 端一致）
   ```
   文件头 (12 + N 字节):
     [0-3]   Magic: "FILE" (0x46 0x49 0x4C 0x45)
     [4-7]   文件名长度 (uint32, little-endian)
     [8-11]  文件大小 (uint32, little-endian)
     [12-N]  文件名 (UTF-8)

   文件数据:
     分块发送，每块 990 字节
   ```

5. **UI 界面**
   - 已配对设备列表
   - 连接/断开按钮
   - 选择文件发送
   - 接收文件保存

#### Android 项目结构（建议）
```
android-app/
├── app/src/main/
│   ├── java/com/example/btfiletransfer/
│   │   ├── MainActivity.kt
│   │   ├── BluetoothService.kt
│   │   └── FileTransferProtocol.kt
│   ├── res/layout/
│   │   └── activity_main.xml
│   └── AndroidManifest.xml
└── build.gradle.kts
```

#### 关键代码片段

**BluetoothService.kt**
```kotlin
class BluetoothService {
    private val SPP_UUID = UUID.fromString("00001101-0000-1000-8000-00805f9b34fb")
    private var socket: BluetoothSocket? = null

    fun connect(device: BluetoothDevice) {
        socket = device.createRfcommSocketToServiceRecord(SPP_UUID)
        socket?.connect()
    }

    fun sendFile(fileName: String, data: ByteArray) {
        val outputStream = socket?.outputStream ?: return

        // 发送文件头
        val nameBytes = fileName.toByteArray(Charsets.UTF_8)
        val header = ByteBuffer.allocate(12 + nameBytes.size)
            .order(ByteOrder.LITTLE_ENDIAN)
            .put("FILE".toByteArray())
            .putInt(nameBytes.size)
            .putInt(data.size)
            .put(nameBytes)
            .array()
        outputStream.write(header)

        // 分块发送数据
        val chunkSize = 990
        var offset = 0
        while (offset < data.size) {
            val end = minOf(offset + chunkSize, data.size)
            outputStream.write(data, offset, end - offset)
            offset = end
        }
    }

    fun receiveFile(): Pair<String, ByteArray>? {
        val inputStream = socket?.inputStream ?: return null

        // 读取文件头
        val headerStart = ByteArray(12)
        inputStream.read(headerStart)

        val buffer = ByteBuffer.wrap(headerStart).order(ByteOrder.LITTLE_ENDIAN)
        val magic = String(headerStart.sliceArray(0..3))
        if (magic != "FILE") return null

        val nameLen = buffer.getInt(4)
        val fileSize = buffer.getInt(8)

        val nameBytes = ByteArray(nameLen)
        inputStream.read(nameBytes)
        val fileName = String(nameBytes, Charsets.UTF_8)

        // 读取文件数据
        val fileData = ByteArray(fileSize)
        var received = 0
        while (received < fileSize) {
            received += inputStream.read(fileData, received, fileSize - received)
        }

        return Pair(fileName, fileData)
    }
}
```

### 7. 使用说明（待测试）

1. 确保两台设备已通过系统蓝牙设置配对
2. 在 OpenHarmony 设备上：
   - 点击"启动服务"等待连接
   - 或点击"刷新"查看已配对设备，选择连接
3. 连接成功后：
   - 点击"发送文件"选择文件发送
   - 收到文件后会显示在列表，可保存

### 8. 参考资料

- [HarmonyOS 蓝牙 SPP 详解](https://www.cnblogs.com/samex/p/18543171)
- [OpenHarmony 蓝牙 API](https://blog.csdn.net/weixin_61845324/article/details/138012654)
- [HarmonyOS NEXT BLE 广播](https://www.cnblogs.com/samex/p/18545311)

### 9. 开发日志

**2026-01-19**
- 初始化项目，尝试 BLE 方案
- 遇到大量 API 兼容性问题
- 切换到 SPP 方案
- 解决权限问题、ArkTS 语法问题
- 解决 structural typing 错误，编译通过
- 发现问题：手机系统蓝牙分享用 OBEX 协议，与 SPP 不兼容
- 需要开发 Android 端配套 App（Kotlin）

### 10. 吐槽：为什么鸿蒙和 Android 通信这么费劲

**根本原因**：鸿蒙想和 Android 切割，但又不得不兼容蓝牙标准。结果就是：

1. **API 乱七八糟** —— OpenHarmony 6.0 的蓝牙 API 改来改去，文档跟不上代码，ArkTS 语法限制一堆
2. **SPP 能用但没生态** —— Android 系统分享走的是 OBEX/OPP，两边协议不通
3. **华为的"遥遥领先"** —— 只在华为设备之间好用（Huawei Share），跨平台就是灾难

**讽刺的是**：
- 蓝牙本来就是通用标准，设计初衷就是跨设备互通
- 结果华为搞了个"自主可控"的 OpenHarmony，反而和 Android 通信更难了
- 最后还得自己写两端 App 才能传个文件

**替代方案**（如果不想写 Android App）：
1. **用 WiFi 直连** —— 两边都支持 HTTP，写个简单 Web 服务器更快
2. **用云盘中转** —— 最蠢但最省事
3. **用 ADB** —— 如果只是调试用

### 11. 设备文件路径与 hdc 调试

#### OpenHarmony 设备路径

| 用途 | 路径 | 说明 |
|------|------|------|
| **下载目录** | `/storage/media/100/local/files/Docs/Download/` | DocumentViewPicker 可访问 |
| **文档目录** | `/storage/media/100/local/files/Docs/Documents/` | DocumentViewPicker 可访问 |
| **图片目录** | `/storage/media/100/local/files/Pictures/` | 相册可见 |
| **应用私有目录** | `/data/app/el2/100/base/com.example.myapplication/files/` | 应用内部存储 |
| **应用安装目录** | `/data/app/el1/bundle/public/com.example.myapplication/` | HAP 安装位置 |
| **临时目录** | `/data/local/tmp/` | hdc 可写，应用不可见 |

#### hdc 常用命令

```powershell
# 发文件到 OpenHarmony 下载目录（应用可通过 DocumentViewPicker 选择）
hdc file send C:\test.txt /storage/media/100/local/files/Docs/Download/test.txt

# 从 OpenHarmony 取文件
hdc file recv /storage/media/100/local/files/Docs/Download/xxx.txt C:\xxx.txt

# 查看目录
hdc shell ls -la /storage/media/100/local/files/Docs/Download/

# 查看应用数据目录
hdc shell ls -la /data/app/el2/100/base/com.example.myapplication/files/
```

#### 注意事项

1. **DocumentViewPicker 只能访问用户目录**（Download、Documents、Pictures 等），不能访问 `/data/local/tmp/`
2. **接收的文件默认只在内存中**，需要用户点"保存"按钮才会写入磁盘
3. **设备时钟可能未同步**（显示 2017 年），不影响功能

### 12. 相关项目

- [Android 端配套应用](https://github.com/lmxxf/Android-Bluetooth-File-Transfer-For-Openharmony-6.0-Bluetooth-App) - Android 端蓝牙文件传输 App

### 13. 下一步

- [ ] 测试大文件传输稳定性
- [ ] 添加传输进度显示
- [ ] 自动保存接收的文件到下载目录
