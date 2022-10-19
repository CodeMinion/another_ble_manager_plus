library another_ble_manager_plus;

import 'dart:async';
import 'dart:collection';
import 'dart:typed_data';

import 'package:another_ble_manager/another_ble_manager.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';

class PlusBleCharacteristic implements IBluetoothGattCharacteristic {
  final BluetoothCharacteristic _characteristic;
  final PlusBleDevice _device;
  final IBluetoothGattService _service;
  StreamSubscription<List<int>>? _charNotificationChannel;

  PlusBleCharacteristic._(
      {required BluetoothCharacteristic characteristic,
        required IBluetoothGattService service,
        required PlusBleDevice device})
      : _device = device,
        _service = service,
        _characteristic = characteristic;

  @override
  Future<Uint8List> read() async {
    List<int> bytesRead = await _characteristic.read();
    return Uint8List.fromList(bytesRead);
  }

  @override
  Future<bool> setNotifyValue(bool notify) async {
    bool success = await _characteristic.setNotifyValue(notify);
    if (success) {
      if (notify) {

        /*
        // If we had one before close and tran new one.
        if (_charNotificationChannel != null) {
          await _charNotificationChannel?.cancel();
        }*/
        // Track the notification stream
        _charNotificationChannel = _characteristic.value.listen((value) {
          // Notify device.
          _device._notifyCharacteristicChanged(
              service: _service,
              characteristic: this,
              value: Uint8List.fromList(value));
        });
      } else {
        // Clean notification stream if any.
        /*
        if (_charNotificationChannel != null) {
          await _charNotificationChannel?.cancel();
          _charNotificationChannel = null;
        }

         */

      }
    }
    return success;
  }

  @override
  Future<void> write(
      {required Uint8List value, bool withoutResponse = false}) async {
    await _characteristic.write(value.toList(),
        withoutResponse: withoutResponse);
  }

  @override
  String getUuid() {
    return _characteristic.uuid.toString().toUpperCase();
  }
}

class PlusBleService implements IBluetoothGattService {
  final BluetoothService _service;
  final PlusBleDevice _device;
  final HashMap<String, IBluetoothGattCharacteristic> _characteristics;

  PlusBleService._(
      {required BluetoothService service, required PlusBleDevice device})
      : _device = device,
        _service = service,
        _characteristics = HashMap() {
    // Load each characteristic
    for (var characteristic in _service.characteristics) {
      IBluetoothGattCharacteristic bleChar = PlusBleCharacteristic._(
          device: _device, service: this, characteristic: characteristic);
      debugPrint(
          "FOUND CHAR: ${characteristic.uuid.toString().toUpperCase()} - SVC ${_service.uuid.toString().toUpperCase()}");
      _characteristics.putIfAbsent(
          characteristic.uuid.toString().toUpperCase(), () => bleChar);
    }
  }

  @override
  IBluetoothGattCharacteristic? getCharacteristic({required String uuid}) {
    return _characteristics[uuid];
  }

  @override
  List<IBluetoothGattCharacteristic> getCharacteristics() {
    return _characteristics.values.toList();
  }

  @override
  String getUuid() => _service.uuid.toString();
}

class PlusBleDevice implements IBleDevice {
  HashMap<String, IBluetoothGattService> _servicesFound;
  IBleCharacteristicChangeListener? _characteristicChangeListener;
  IBleDeviceConnectionStateChangeListener?
  _bleDeviceConnectionStateChangeListener;
  StreamSubscription<BluetoothDeviceState>? _connectionStateStream;
  BluetoothDevice device;
  BleConnectionState _state = BleConnectionState.unknown;

  PlusBleDevice({required this.device}) : _servicesFound = HashMap();

  @override
  Future<bool> disableCharacteristicIndicate(
      {required String serviceUuid, required String charUuid}) async {
    // TODO: implement disableCharacteristicIndicate
    throw UnsupportedError("disableCharacteristicIndicate not yet supported");
  }

  @override
  Future<bool> disableCharacteristicNotify(
      {required String serviceUuid, required String charUuid}) async {
    return await _servicesFound[serviceUuid]
        ?.getCharacteristic(uuid: charUuid)
        ?.setNotifyValue(false) ??
        false;
  }

  @override
  Future<IBleDevice> connect(
      {Duration duration = const Duration(seconds: 2),
        bool autoConnect = false}) async {
    await device.connect();

    // Listen for connection state changes.
    _connectionStateStream = device.state.listen((event) {
      debugPrint("Device State Received: $event");
      _bleDeviceConnectionStateChangeListener?.onDeviceConnectionStateChanged(
          device: this, newGattState: event.toBleConnectionState());
    })
      ..onDone(() {
        debugPrint("Device Stream Closed");
      });

    return this;
  }

  @override
  Future<IBleDevice> disconnect() async {
    await device.disconnect();
    return this;
  }

  @override
  Future<void> discoverServices({bool refresh = false}) async {
    if (refresh) {
      _servicesFound = HashMap();
    }
    List<BluetoothService> services = await device.discoverServices();
    // Track service
    if (_servicesFound.isEmpty) {
      for (var service in services) {
        _servicesFound.putIfAbsent(service.uuid.toString().toUpperCase(),
                () => PlusBleService._(device: this, service: service));
      }
    }

    debugPrint("Services $_servicesFound");
  }

  @override
  Future<bool> enableCharacteristicIndicate(
      {required String serviceUuid, required String charUuid}) {
    // TODO: implement enableCharacteristicIndicate
    throw UnsupportedError("enableCharacteristicIndicate not yet supported");
  }

  @override
  Future<bool> enableCharacteristicNotify(
      {required String serviceUuid, required String charUuid}) async {
    return await _servicesFound[serviceUuid]
        ?.getCharacteristic(uuid: charUuid)
        ?.setNotifyValue(true) ??
        false;
  }

  @override
  BleConnectionState getConnectionState() {
    return _state;
  }

  @override
  Future<IBluetoothGattCharacteristic> readCharacteristic(
      {required String serviceUuid, required String charUuid}) async {
    IBluetoothGattCharacteristic? characteristic =
    _servicesFound[serviceUuid]?.getCharacteristic(uuid: charUuid);

    if (characteristic == null) {
      throw BluetoothGattCharacteristicNotFound(
          serviceUuid: serviceUuid, uuid: charUuid);
    }

    await characteristic.read();
    return characteristic;
  }

  @override
  Future<IBleDevice> reconnect() async {
    await device.connect();
    return this;
  }

  @override
  void setOnCharacteristicChangeListener(
      {IBleCharacteristicChangeListener? listener}) {
    _characteristicChangeListener = listener;
  }

  @override
  void setOnDeviceConnectionsStateChangeListener(
      {IBleDeviceConnectionStateChangeListener? listener}) {
    _bleDeviceConnectionStateChangeListener = listener;
  }

  @override
  Future<IBluetoothGattCharacteristic> writeCharacteristic(
      {required String serviceUuid,
        required String charUuid,
        required Uint8List value}) async {
    IBluetoothGattCharacteristic? characteristic =
    _servicesFound[serviceUuid]?.getCharacteristic(uuid: charUuid);

    if (characteristic == null) {
      throw BluetoothGattCharacteristicNotFound(
          serviceUuid: serviceUuid, uuid: charUuid);
    }

    await characteristic.write(value: value);
    return characteristic;
  }

  void _notifyCharacteristicChanged(
      {required IBluetoothGattService service,
        required IBluetoothGattCharacteristic characteristic,
        required Uint8List value}) {
    _characteristicChangeListener?.onCharacteristicChanged(
        device: this,
        service: service,
        characteristic: characteristic,
        value: value);
  }

  @override
  String getName() {
    return device.name;
  }

  @override
  Stream<BleConnectionState> getConnectionStates() {
    return device.state.map((event) {
      _state = event.toBleConnectionState();
      return _state;
    });
  }

  @override
  String getId() => device.id.id;
}

class PlusBleAdapter implements IBleAdapter {
  static PlusBleAdapter? _instance;

  final HashMap<String, PlusBleDevice> _foundDevices = HashMap();
  PlusBleAdapter._();

  static PlusBleAdapter getInstance() {
    return _instance ??= PlusBleAdapter._();
  }

  @override
  Stream<List<IBleDevice>> getScanResults() {
    // TODO Consider tracking the device during the map, otherwise we might lose any conneciton state.
    return FlutterBluePlus.instance.scanResults
        .map((resultList) => resultList.map((result) {
      String deviceId = result.device.id.id;
      // If device is not tracked track
      if (_foundDevices.containsKey(deviceId)) {
        return _foundDevices[deviceId]!;
      }
      else {
        PlusBleDevice device = PlusBleDevice(device: result.device);
        _foundDevices.putIfAbsent(deviceId, () => device);
        return device;
      }
    }).toList());
  }

  @override
  Future<void> startScan() async {
    // Clean current list on every scan
    _foundDevices.clear();
    await FlutterBluePlus.instance.startScan();
  }

  @override
  Future<void> stopScan() async {
    await FlutterBluePlus.instance.stopScan();
  }
}

extension on BluetoothDeviceState {
  BleConnectionState toBleConnectionState() {
    BleConnectionState state = BleConnectionState.unknown;

    if (this == BluetoothDeviceState.disconnected) {
      state = BleConnectionState.disconnected;
    } else if (this == BluetoothDeviceState.connected) {
      state = BleConnectionState.connected;
    } else if (this == BluetoothDeviceState.connecting) {
      state = BleConnectionState.connecting;
    } else if (this == BluetoothDeviceState.disconnecting) {
      state = BleConnectionState.disconnecting;
    }
    return state;
  }
}

