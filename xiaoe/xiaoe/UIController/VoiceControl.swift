//
//  VoiceControl.swift
//  xiaoe
//
//  Created by 何辉 on 2017/5/10.
//  Copyright © 2017年 何辉. All rights reserved.

/*
  把烟熄灭了吧，对身体会好一点，虽然这样很难度过想你的夜~
  舍不得我们拥抱的照片，却又不想让自己看见，把它藏在相框的后面~
  把窗户打开吧，对心情会好一点,这样我还能微笑着和你分别~
  那是我最喜欢的唱片，你说那只是一段音乐，却会让我在以后想念~
  说着付出生命的誓言，回头看看繁华的世界，爱你的每个瞬间像飞驰而过的地铁~
  说过不会掉下的泪水，现在沸腾着我的双眼，爱你的虎口我脱离了危险~
 */
//
// - 语音控制 & 语音留言 模块
import UIKit

import Speech

import AVFoundation

import ETILinkSDK

class VoiceControl: BaseViewController  , SFSpeechRecognizerDelegate , ChatDataSource , LEDReceiveDelegete{
    
    let TAG = "VoiceControl"

    let speechRecognizer = SFSpeechRecognizer(locale: Locale.init(identifier: "zh-cn"))
    
    @IBOutlet weak var foundtiontxt: UILabel!
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    
    private var recognitionTask: SFSpeechRecognitionTask?
    
    private let audioEngine = AVAudioEngine()
    
    var audioRecorder:AVAudioRecorder! //录音类
    
    var audioPlayer:AVAudioPlayer! //用于播放录音
    
    var mainViewController : ViewController!
    
    var SoundURL : URL?   //用来临时存储录音路径URL
    
    var WhoAmI = VOICE_CONTROL  //语音控制 或 语音留言
    
    @IBOutlet weak var foundationimg: UIImageView!
    
    
    // - 定义音频的编码参数，这部分比较重要，否则开发板播放的声音有失真
    let recordSettings: [String: Any] = [AVSampleRateKey: NSNumber(value: 8000),//采样率
        AVFormatIDKey: NSNumber(value: kAudioFormatLinearPCM),//音频格式
        AVLinearPCMBitDepthKey: NSNumber(value: 16),//采样位数
        AVNumberOfChannelsKey: NSNumber(value: 1),//通道数
        AVEncoderAudioQualityKey: NSNumber(value: AVAudioQuality.medium.rawValue)//录音质量
    ]
    
    var tableView:TableView!
    
    var Chats:NSMutableArray!
    
    var me:UserInfo!
    
    var you:UserInfo!
    
    var ListenResult = "" //语音识别结果
    
    let defaults = UserDefaults.standard
    
    var DeviceUid = "" //设备ID
    
    @IBOutlet weak var microphoneButton: UIButton!
   
    @IBOutlet weak var ParentView: UIView!
    
    @IBAction func microphoneTapped(_ sender: Any) {
        if WhoAmI == VOICE_CONTROL { // - 语音控制模块
            if audioEngine.isRunning { // 停止识别(停止录音-->更新回话列表)----->如果含有“温度”||“湿度”||“大气”||“开关灯”，则发送查询指令到设备,没有以上字符，则显示不能识别指令。
                dismissRecordImage()
                audioEngine.stop()
                recognitionRequest?.endAudio()
                microphoneButton.setTitle(CLICK_SPEAK, for: .normal)
                microphoneButton.setTitleColor(UIColor.black, for: .normal)
                // - 停止录音
                StopLuYin()
                // - 新增一项到对话列表----->更新视图
                let Sound =  MessageItem(recordUrl:SoundURL,user:me, date:Date(timeIntervalSinceNow:0), mtype:.mine)
                Chats.add(Sound)
                tableView.reloadData()
            } else {
                ShowRecordImage()
                startRecording()   //开始语音识别
                LuYin()   //开始录音
                microphoneButton.setTitle(CLICK_END, for: .normal)
                microphoneButton.setTitleColor(UIColor.red, for: .normal)
            }
        }else{// - 语音留言模块
            if microphoneButton.currentTitle! == CLICK_SPEAK {
                ShowRecordImage()
                LuYin()
                microphoneButton.setTitle(CLICK_END, for: .normal)
                microphoneButton.setTitleColor(UIColor.red, for: .normal)
            }else{
                dismissRecordImage()
                microphoneButton.setTitle(CLICK_SPEAK, for: .normal)
                microphoneButton.setTitleColor(UIColor.black, for: .normal)
                StopLuYin()
                let Sound =  MessageItem(recordUrl:SoundURL,user:me, date:Date(timeIntervalSinceNow:0), mtype:.mine)
                Chats.add(Sound)
                tableView.reloadData()
                sendFileToDevice(filepath_url: SoundURL!)
            }
        }
        
    }
    override func viewDidLoad() {
        super.viewDidLoad()
        if WhoAmI == VOICE_CONTROL {
            self.title = "语音控制"
        }else{
            self.title = "语音留言"
            foundationimg.image = UIImage(named:"语音留言.png")
            foundtiontxt.text = "语音留言"
        }
        
        
        DeviceUid = defaults.string(forKey: DEVICE_ID_KEY)!
        ViewController.isResponse = false //此处设置主页不需要响应收到的消息(全部由此页面处理)
        Chats = NSMutableArray()
        // Do any additional setup after loading the view.
        SFSpeechRecognizer.requestAuthorization { (authStatus) in  //
            var isButtonEnabled = false
            switch authStatus {  //5
            case .authorized:
                isButtonEnabled = true
            case .denied:
                isButtonEnabled = false
                print("User denied access to speech recognition")
            case .restricted:
                isButtonEnabled = false
                print("Speech recognition restricted on this device")
            case .notDetermined:
                isButtonEnabled = false
                print("Speech recognition not yet authorized")
            }
            OperationQueue.main.addOperation() {
                self.microphoneButton.isEnabled = isButtonEnabled
            }
        }
        
        mainViewController = self.navigationController!.viewControllers[0] as! ViewController //取得ViewContrallor实例（使用appManage对象）
        mainViewController.leddelegate = self
        setupChatTable()
    }

    override func didReceiveMemoryWarning() {
        super.didReceiveMemoryWarning()

    }
    
    func showPrint(_ data:String){
        print("\(TAG) \(data)\n")
    }
    
    // - 使用speech framework实现语音转文字
    func startRecording() {
        if recognitionTask != nil {
            recognitionTask?.cancel()
            recognitionTask = nil
        }
        let audioSession = AVAudioSession.sharedInstance()
        do {
            try audioSession.setCategory(AVAudioSessionCategoryRecord)
            try audioSession.setMode(AVAudioSessionModeMeasurement)
            try audioSession.setActive(true, with: .notifyOthersOnDeactivation)
        } catch {
            print("audioSession properties weren't set because of an error.")
        }
        recognitionRequest = SFSpeechAudioBufferRecognitionRequest()
        guard let inputNode = audioEngine.inputNode else {
            fatalError("Audio engine has no input node")
        }
       guard let recognitionRequest = recognitionRequest else {
            fatalError("Unable to create an SFSpeechAudioBufferRecognitionRequest object")
        }
        recognitionRequest.shouldReportPartialResults = true
        recognitionTask = speechRecognizer?.recognitionTask(with: recognitionRequest, resultHandler: { (result, error) in
            var isFinal = false
            if result != nil {
                self.ListenResult = (result?.bestTranscription.formattedString)!
                isFinal = (result?.isFinal)!
                self.showPrint("识别的结果是:  \(self.ListenResult)")
            }
            if isFinal {//语音识别完成
                self.showPrint("最终识别结果是: \(self.ListenResult)")
                self.ListenResult = (result?.bestTranscription.formattedString)!
                self.DisPoseListenResult()
                self.audioEngine.stop()
                inputNode.removeTap(onBus: 0)
                self.recognitionRequest = nil
                self.recognitionTask = nil
            }
            if error != nil {
                self.showPrint("识别 error")
                self.DisPoseListenResult()
                self.audioEngine.stop()
                inputNode.removeTap(onBus: 0)
                self.recognitionRequest = nil
                self.recognitionTask = nil
            }
        })
        let recordingFormat = inputNode.outputFormat(forBus: 0)
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: recordingFormat) { (buffer, when) in
            self.recognitionRequest?.append(buffer)
        }
        audioEngine.prepare()
        do {
            try audioEngine.start()
        } catch {
            print("audioEngine couldn't start because of an error.")
        }
        
    }
    
    func speechRecognizer(_ speechRecognizer: SFSpeechRecognizer, availabilityDidChange available: Bool) {
        if available {
            microphoneButton.isEnabled = true
        } else {
            microphoneButton.isEnabled = false
        }
    }
    
    func setupChatTable()
    {
        self.view.bringSubview(toFront: microphoneButton) //将发送button移到最上层，避免被其他视图遮住
        self.tableView = TableView(frame:CGRect(x: 0, y: 0, width: self.view.frame.size.width, height:self.ParentView.frame.height - microphoneButton.frame.height-10), style: .plain)
        //创建一个重用的单元格
        self.tableView!.register(TableViewCell.self, forCellReuseIdentifier: "ChatCell")
        me = UserInfo(name:"me" ,logo:("头像_设备.png"))
        you  = UserInfo(name:"you", logo:("头像_设备.png"))
        if WhoAmI == VOICE_CONTROL {
            let fouth =  MessageItem(body:"语音控制提供查询温湿度、大气压和控制灯光开关功能！",user:me, date:Date(timeIntervalSinceNow:0), mtype:.mine)
            Chats.add(fouth)
            self.tableView.chatDataSource = self
            self.tableView.reloadData()
            self.ParentView.addSubview(self.tableView)
        }else{
            let fouth =  MessageItem(body:"请确认开发板处于4档位，且跳线帽正确才能播放语音留言。",user:me, date:Date(timeIntervalSinceNow:0), mtype:.mine)
            Chats.add(fouth)
            self.tableView.chatDataSource = self
            self.tableView.reloadData()
            self.ParentView.addSubview(self.tableView)
        }
       
    }

    func rowsForChatTable(_ tableView:TableView) -> Int
    {
        return self.Chats.count
    }
    
    
    func chatTableView(_ tableView:TableView, dataForRow row:Int) -> MessageItem
    {
        return Chats[row] as! MessageItem
    }
    // - 构建录音保存URL
    func directoryURL() -> URL? {
        //定义并构建一个url来保存音频，音频文件名为ddMMyyyyHHmmss.wav
        //根据时间来设置存储文件名
        let currentDateTime = Date()
        let formatter = DateFormatter()
        formatter.dateFormat = "ddMMyyyyHHmmss"
        let recordingName = formatter.string(from: currentDateTime)+".wav"
        
        //获取Document目录
        let docDir = NSSearchPathForDirectoriesInDomains(.documentDirectory,.userDomainMask, true)[0]
        let filepath = docDir + "/\(recordingName)"
        let soundURL = URL(string:filepath)
        self.SoundURL = soundURL
        return soundURL
    }
    // - 开始录音
    func LuYin(){
        let audioSession = AVAudioSession.sharedInstance()
        do {
            try audioSession.setCategory(AVAudioSessionCategoryPlayAndRecord)
            try audioRecorder = AVAudioRecorder(url: self.directoryURL()!,settings: recordSettings)//初始化实例
            audioRecorder.prepareToRecord()//准备录音
        } catch {
            
        }
        if !audioRecorder.isRecording {
            let audioSession = AVAudioSession.sharedInstance()
            do {
                try audioSession.setActive(true)
                audioRecorder.record()
            } catch {
            }
        }
    }
    // - 停止录音
    func StopLuYin(){
        audioRecorder.stop()
        let audioSession = AVAudioSession.sharedInstance()
        do {
            try audioSession.setActive(false)
        } catch {
        }
    }
    
    // - 处理识别过后的文字  能识别成指令则发送，否则给出对应提示
    
    func DisPoseListenResult(){
        print("处理的文字是： \(self.ListenResult)")
        if ListenResult.contains("温") || ListenResult.contains("湿") || ListenResult.contains("度"){ // 查询温湿度
            sendTempOrAirReq(isTemp: true)
        }else if ListenResult.contains("气压") || ListenResult.contains("大气") { //查询大气压
            sendTempOrAirReq(isTemp: false)
            
        }else if ListenResult.contains("关灯")||ListenResult.contains("关"){//关灯
            OpenOrCloseLight(isOpen:false)
            
        }else if ListenResult.contains("开灯")||ListenResult.contains("开"){//开灯
            OpenOrCloseLight(isOpen:true)
        }else{//指令无法识别
            let item =  MessageItem(body:"指令无法识别",user:you, date:Date(timeIntervalSinceNow:0), mtype:.someone)
            Chats.add(item)
            tableView.reloadData()
        }
        self.ListenResult = "" //处理了此条消息，设备内容至空
    }
    // - 收到led控制反馈--->此处不处理
    func onLEDReceive(body: LEDControllerResBody) {
        
    }
    // - 收到查询反馈指令
    func onQueryReceive(body: Body) {
        if body is TemperatureAndHumidityResBody { //温湿度查询回复
            let tempbody = body as! TemperatureAndHumidityResBody
            let showstr = "温度 (℃)  \(tempbody.tempeInt).\(tempbody.tempeDec)℃\n\n湿度 (RH) \(tempbody.humInt).\(tempbody.hunDec)%"
            let item = MessageItem(body:showstr as NSString,user:you, date:Date(timeIntervalSinceNow:0), mtype:.someone)
            Chats.add(item)
            tableView.reloadData()
        }else if body is AirResBody {//大气压查询回复
            let airbody = body as! AirResBody
            let showstr = "大气压 (Pa) \(airbody.air) \n\n海拔 (m) \(airbody.high)"
            let item = MessageItem(body:showstr as NSString,user:you, date:Date(timeIntervalSinceNow:0), mtype:.someone)
            Chats.add(item)
            tableView.reloadData()
        }else if body is RGBControllerResBody{//灯光控制反馈
            let item = MessageItem(body:"灯光控制成功",user:you, date:Date(timeIntervalSinceNow:0), mtype:.someone)
            Chats.add(item)
            tableView.reloadData()
        }
    }
    
    // - 发送温湿度或者大气压查询指令
    // - isTemp = true    查询温湿度
    // - isTemp = false   查询大气压
    
    func sendTempOrAirReq(isTemp:Bool){
        
        var instruction : Instruction?
        
        if isTemp {
             instruction = Instruction.Builder().setCmd(cmd: Instruction.Cmd.QUERY).setBody(body: TemperatureAndHumidityReqBody(data1:Instruction.RequestType.BOTH)).createInstruction()
        }else{
             instruction = Instruction.Builder().setCmd(cmd: Instruction.Cmd.QUERY).setBody(body: AirReqBody(data1:Instruction.RequestType.AIR)).createInstruction()
        }
       
       let message = ETMessage(bytes : instruction!.toByteArray())
        
       mainViewController.mAppManager.etManager.chatTo(DeviceUid, message: message) { (error) in
            guard error == nil else {
                
                let item =  MessageItem(body:"查询出错",user:self.you, date:Date(timeIntervalSinceNow:0), mtype:.someone)
                self.Chats.add(item)
                self.tableView.reloadData()
                
                return
            }
            print("chatto [\(self.DeviceUid)], content: \(message) ")
        }
      
    }
    // - 开关灯
    func OpenOrCloseLight(isOpen:Bool){
        var instruction = Instruction.Builder().setCmd(cmd: Instruction.Cmd.CONTROL).setBody(body: RGBControllerReqBody(color:LIGHT_COLORS[1])).createInstruction()
        if !isOpen {//关灯
            instruction = Instruction.Builder().setCmd(cmd: Instruction.Cmd.CONTROL).setBody(body: RGBControllerReqBody(color:LIGHT_COLORS[13])).createInstruction()
        }
        
        let message = ETMessage(bytes : instruction!.toByteArray())
        
        mainViewController.mAppManager.etManager.chatTo(DeviceUid, message: message) { (error) in
            guard error == nil else {
                let item =  MessageItem(body:"灯光控制失败",user:self.you, date:Date(timeIntervalSinceNow:0), mtype:.someone)
                self.Chats.add(item)
                self.tableView.reloadData()
                return
            }
            print("chatto [\(self.DeviceUid)], content: \(message) ")
        }
       
    }
    
    //播放此条录音
    func PlaySound(url:URL){
        do {
            try audioPlayer = AVAudioPlayer(contentsOf: url)
            
             audioPlayer.play()
            
        } catch {
        }
    }
     let emptyView = UIView() //用来装声音图片的视图
     let imageView = UIImageView() //录音时显示的image
    //展示录音识别中图片
    func ShowRecordImage(){
        let emptyvieworign = CGPoint(x: 0, y: 0)
        let emptyviewsize = CGSize(width: self.view.frame.width, height: self.view.frame.height - microphoneButton.frame.height - 10)
        emptyView.frame = CGRect(origin: emptyvieworign, size: emptyviewsize)
        emptyView.backgroundColor = UIColor.clear
        emptyView.isUserInteractionEnabled = true
        //定义图片的大小和位置
        let imageorign = CGPoint(x : 0.3147*self.view.frame.width, y : 0.5178*self.view.frame.height)
        let imagesize = CGSize(width: 0.3815*self.view.frame.width,height: 0.3815*self.view.frame.width)
        imageView.frame = CGRect(origin : imageorign, size: imagesize)
        imageView.image = UIImage(named:"识别中.png")
        
        emptyView.addSubview(imageView)
        self.view.addSubview(emptyView)
    }
    //移除录音识别中图片
    func dismissRecordImage(){
        imageView.removeFromSuperview()
        emptyView.removeFromSuperview()
    }
    //发送语音文件到设备
    func sendFileToDevice(filepath_url:URL){
        let filepath = filepath_url.absoluteString
      
        self.mainViewController.mAppManager.etManager.fileTo(DeviceUid, filePath: filepath) { (fileInfo, error) in
            guard error == nil else {
                let fouth =  MessageItem(body:"留言发送失败",user:self.you, date:Date(timeIntervalSinceNow:0), mtype:.someone)
                self.Chats.add(fouth)
                self.tableView.reloadData()
                return
            }
            let fouth =  MessageItem(body:"留言发送成功",user:self.you, date:Date(timeIntervalSinceNow:0), mtype:.someone)
            self.Chats.add(fouth)
            self.tableView.reloadData()
        }
    }
}
