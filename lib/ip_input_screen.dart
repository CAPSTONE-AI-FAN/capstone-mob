import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import './shared_prefs_service.dart';

class IpInputScreen extends StatefulWidget {
  final Function(String) onIpSaved;

  const IpInputScreen({Key? key, required this.onIpSaved}) : super(key: key);

  @override
  _IpInputScreenState createState() => _IpInputScreenState();
}

class _IpInputScreenState extends State<IpInputScreen> {
  final _formKey = GlobalKey<FormState>();
  final List<TextEditingController> _ipControllers = List.generate(
    4,
    (_) => TextEditingController(),
  );
  final List<FocusNode> _focusNodes = List.generate(
    4,
    (_) => FocusNode(),
  );

  bool _isLoading = false;

  @override
  void initState() {
    super.initState();

    // 저장된 IP가 있는지 확인하고 불러오기
    SharedPrefsService.getBrokerIp().then((savedIp) {
      if (savedIp != null && savedIp.isNotEmpty) {
        final ipParts = savedIp.split('.');
        if (ipParts.length == 4) {
          for (int i = 0; i < 4; i++) {
            setState(() {
              _ipControllers[i].text = ipParts[i];
            });
          }
        }
      }
    });
  }

  @override
  void dispose() {
    for (var controller in _ipControllers) {
      controller.dispose();
    }
    for (var focusNode in _focusNodes) {
      focusNode.dispose();
    }
    super.dispose();
  }

  // IP 부분이 유효한지 확인 (0-255 범위 확인)
  String? _validateIpPart(String? value) {
    if (value == null || value.isEmpty) {
      return '필수';
    }

    final intValue = int.tryParse(value);
    if (intValue == null || intValue < 0 || intValue > 255) {
      return '0-255';
    }

    return null;
  }

  // 전체 IP 주소 생성 및 저장
  Future<void> _saveIpAddress() async {
    if (_formKey.currentState!.validate()) {
      setState(() {
        _isLoading = true;
      });

      // 4개 부분을 점으로 연결하여 IP 주소 생성
      final ip = _ipControllers.map((c) => c.text.trim()).join('.');

      try {
        await SharedPrefsService.saveBrokerIp(ip);
        widget.onIpSaved(ip);
      } catch (e) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('IP 주소 저장 중 오류가 발생했습니다: $e')),
        );
      } finally {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('MQTT 브로커 설정'),
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(20.0),
          child: Form(
            key: _formKey,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  'MQTT 브로커 IP 주소를 입력해주세요',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
                SizedBox(height: 30),

                // 4개의 IP 부분 입력 필드 (점으로 구분)
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: List.generate(4, (index) {
                    return Expanded(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 4.0),
                        child: TextFormField(
                          controller: _ipControllers[index],
                          focusNode: _focusNodes[index],
                          decoration: InputDecoration(
                            border: OutlineInputBorder(),
                            contentPadding: EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 16,
                            ),
                          ),
                          textAlign: TextAlign.center,
                          keyboardType: TextInputType.number,
                          inputFormatters: [
                            FilteringTextInputFormatter.digitsOnly,
                            LengthLimitingTextInputFormatter(3),
                          ],
                          validator: _validateIpPart,
                          onChanged: (value) {
                            // 3자리 숫자를 입력하거나 입력값이 있을 때 다음 필드로 포커스 이동
                            if ((value.length == 3 ||
                                    (int.tryParse(value) ?? 0) > 25) &&
                                index < 3) {
                              _focusNodes[index + 1].requestFocus();
                            }
                          },
                        ),
                      ),
                    );
                  })
                      .expand((widget) => [
                            widget,
                            if (widget != _buildIpPartField(3))
                              Text('.',
                                  style: TextStyle(
                                      fontSize: 24,
                                      fontWeight: FontWeight.bold)),
                          ])
                      .toList()
                    ..removeLast(),
                ),

                SizedBox(height: 30),
                _isLoading
                    ? CircularProgressIndicator()
                    : ElevatedButton(
                        onPressed: _saveIpAddress,
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 24.0,
                            vertical: 12.0,
                          ),
                          child: Text(
                            '저장하고 계속하기',
                            style: TextStyle(fontSize: 16),
                          ),
                        ),
                      ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // IP 부분 입력 필드 생성 함수
  Widget _buildIpPartField(int index) {
    return Expanded(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4.0),
        child: TextFormField(
          controller: _ipControllers[index],
          focusNode: _focusNodes[index],
          decoration: InputDecoration(
            border: OutlineInputBorder(),
            contentPadding: EdgeInsets.symmetric(
              horizontal: 12,
              vertical: 16,
            ),
          ),
          textAlign: TextAlign.center,
          keyboardType: TextInputType.number,
          inputFormatters: [
            FilteringTextInputFormatter.digitsOnly,
            LengthLimitingTextInputFormatter(3),
          ],
          validator: _validateIpPart,
          onChanged: (value) {
            // 3자리 숫자를 입력하거나 입력값이 있을 때 다음 필드로 포커스 이동
            if ((value.length == 3 || (int.tryParse(value) ?? 0) > 25) &&
                index < 3) {
              _focusNodes[index + 1].requestFocus();
            }
          },
        ),
      ),
    );
  }
}
