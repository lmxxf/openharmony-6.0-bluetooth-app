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

### 6. 待解决问题

当前编译错误：
```
arkts-no-structural-typing
Structural typing is not supported
At File: BluetoothService.ets:275:70
```

可能原因：ArkTS 对类型转换有严格限制，需要进一步调整代码。

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
- 当前卡在 structural typing 错误
