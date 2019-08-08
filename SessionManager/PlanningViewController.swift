//
//  ViewController.swift
//  SessionManager
//
//  Created by Dani Rangelov on 22.07.19.
//  Copyright © 2019 Dani Rangelov. All rights reserved.
//

import UIKit
import AVFoundation
import AudioToolbox
import MediaPlayer
import UserNotifications

class PlanningViewController: UIViewController {

    @IBOutlet weak var scrollview: UIScrollView!
    @IBOutlet weak var startTimePicker: UIDatePicker!
    @IBOutlet weak var endTimePicker: UIDatePicker!
    @IBOutlet weak var sessionsCountPicker: UIPickerView!
    @IBOutlet weak var groupsCountPicker: UIPickerView!
    @IBOutlet weak var earlyNotification: UIPickerView!
    @IBOutlet weak var startButton: UIButton!
    @IBOutlet weak var collectionView: UICollectionView!
    @IBOutlet weak var collectionViewHeight: NSLayoutConstraint!
    @IBOutlet weak var timersView: UIView!
    @IBOutlet weak var currentTimeLabel: UILabel!
    @IBOutlet weak var nextAlarmLabel: UILabel!
    @IBOutlet weak var sessionEndTimeLabel: UILabel!
    
    enum Constants {
        static let sessionsMax = 7
        static let groupsMax = 8
        static let groupsColors = [UIColor.white, UIColor.blue, UIColor(red: 0.5, green: 0.5, blue: 1, alpha: 1), UIColor.orange, UIColor.red]
        static let notificationAdvanceMax = 10
        static let sessionDurationMax = 60
    }
    
    let calendar = Calendar.current
    var components = DateComponents()
    let dateFormatter = DateFormatter()
    
    
    private var audioPlayer = AVAudioPlayer()
    private let soundPath1 = Bundle.main.path(forResource: "alarm_1", ofType: "mp3")
    private let soundPath2 = Bundle.main.path(forResource: "alarm_2", ofType: "mp3")
    private let soundPath3 = Bundle.main.path(forResource: "alarm_3", ofType: "mp3")
    
    let notificationCenter = UNUserNotificationCenter.current()
    let options: UNAuthorizationOptions = [.alert, .sound, .badge]
    
    var sessions = [Date]()
    var nextSessionEnd: Date?
    var nextEarlyWarning: Date?
    
    var sessionsCount: Int {
        return sessionsCountPicker.selectedRow(inComponent: 0) + 1
    }
    
    var groupsCount: Int {
        return groupsCountPicker.selectedRow(inComponent: 0) + 1
    }
    
    var earlyWarningSelection: Int {
        return earlyNotification.selectedRow(inComponent: 0) + 1
    }
    
    var isStarted = false
    private var timer = Timer()
    
    
    //MARK: -
    override func viewDidLoad() {
        super.viewDidLoad()
        
        setupAudioPlayer()
        setupLocalNotifications()
        
        startTimePicker.date = calendar.date(bySettingHour: 10, minute: 0, second: 0, of: Date())!
        endTimePicker.date = calendar.date(bySettingHour: 18, minute: 0, second: 0, of: Date())!
        
        startButton.layer.cornerRadius = 5
        startButton.clipsToBounds = true
        
        dateFormatter.dateFormat = "HH:mm"
        
        loadState()
        
        handleTimersState(isStarted: isStarted)
    }

    private func setupAudioPlayer() {
        do {
            try AVAudioSession.sharedInstance().setCategory(.playback, options: [.duckOthers, .defaultToSpeaker])
            try AVAudioSession.sharedInstance().setActive(true)
            UIApplication.shared.beginReceivingRemoteControlEvents()
            NSLog("Audio Session is active")
        } catch {
            NSLog("Audio Session error: \(error)")
        }
    }
    
    private func setupLocalNotifications() {
        notificationCenter.requestAuthorization(options: options) {
            (didAllow, error) in
            if !didAllow {
                print("User has declined notifications")
            }
        }
    }
    
    private func loadState() {
        
    }
    
    private func saveState() {
        
    }
    
    private func updateDataModel() {
        let startDate = startTimePicker.date
        let endDate = endTimePicker.date
        let timeInterval = Int(endDate.timeIntervalSince(startDate))
        let totalMinutes = timeInterval/60
        let totalRuns = sessionsCount * groupsCount
        let sessionTime = totalMinutes/totalRuns
        
        sessions.removeAll()
        
        var nextSession = startDate
        sessions.append(nextSession)
        
        while nextSession < endDate {
            if let date = nextSessionDate(currentSession: nextSession, sessionDuration: sessionTime), date != nextSession {
                nextSession = date
                sessions.append(nextSession)
            }
        }
    }
    
    private func nextSessionDate(currentSession: Date, sessionDuration: Int) -> Date? {
        return calendar.date(byAdding: .minute, value: sessionDuration, to: currentSession)
    }
    
    private func formatedDateString(date: Date) -> String {
        return dateFormatter.string(from: date)
    }
    
    private func handleTimersState(isStarted: Bool) {
        self.isStarted = isStarted
        if isStarted {
            saveState()
            
            startButton.setTitle("STOP", for: .normal)
            scrollview.scrollRectToVisible(timersView.frame, animated: true)
            startButton.backgroundColor = UIColor(red: 1, green: 0.3, blue: 0.3, alpha: 1)
            timer = Timer.scheduledTimer(timeInterval: 1.0, target: self, selector:#selector(self.tick) , userInfo: nil, repeats: true)
            
            
            let allEarlyWarnings = sessions.compactMap { (date) -> Date? in
                return calculateEarlyWarningDate(date: date, earlyWarningPeriod: earlyWarningSelection)
            }
            
            print(sessions)
            
            scheduleLocalNotifications(dates: allEarlyWarnings)
            notificationCenter.getPendingNotificationRequests { (localNotifications) in
                print("All notifications count \(localNotifications.count), arrayCount = \(allEarlyWarnings.count)")
            }
            
            
            let nextSessionAlarms = calculateNextSessionAlarms(referenceDate: Date(), earlyWarningPeriod: earlyWarningSelection)
            nextSessionEnd = nextSessionAlarms.nextSessionEnd
            nextEarlyWarning = nextSessionAlarms.earlyWarning
        } else {
            startButton.setTitle("START", for: .normal)
            scrollview.scrollRectToVisible(CGRect(x: 0, y: 0, width: 20, height: 20), animated: true)
            startButton.backgroundColor = UIColor(red: 0.3, green: 0.3, blue: 1, alpha: 1)
            timer.invalidate()
            
            removeAllNotifications()
        }
    }
    
    func calculateNextSessionAlarms(referenceDate: Date, earlyWarningPeriod: Int) -> (nextSessionEnd: Date?, earlyWarning: Date?) {
        let futureAlarms = sessions.filter( { $0 > referenceDate } )
        let nextAlarmDate = futureAlarms.sorted().first
        
        var nextEarlyWarning: Date? = nil
        if let nextAlarmDate = nextAlarmDate {
            nextEarlyWarning = calculateEarlyWarningDate(date: nextAlarmDate, earlyWarningPeriod: earlyWarningPeriod)
        }
        
        return (nextSessionEnd: nextAlarmDate, earlyWarning: nextEarlyWarning)
    }
    
    func calculateEarlyWarningDate(date: Date, earlyWarningPeriod: Int) -> Date? {
        return calendar.date(byAdding: .minute, value: -earlyWarningPeriod, to: date)
    }
    
    //MARK: - Actions
    @IBAction func datepickerValueChanged(_ sender: UIDatePicker) {
        updateDataModel()
        collectionView.reloadData()
    }
    
    @IBAction func startButtonPressed(_ sender: UIButton) {
        handleTimersState(isStarted: !isStarted)
    }

    
    //MARK: - Timer
    func timeString(time:TimeInterval) -> String {
        let timeAbsolute = abs(time)
        let hours = Int(timeAbsolute) / 3600
        let minutes = Int(timeAbsolute) / 60 % 60
        let seconds = Int(timeAbsolute) % 60
        return String(format:"%02i:%02i:%02i", hours, minutes, seconds)
    }
    
    @objc func tick() {
        let date = Date()
        print("Timer check")
        guard let nextAlarmDate = nextSessionEnd else {
            isStarted = false
            handleTimersState(isStarted: isStarted)
            return
        }
        
        currentTimeLabel.text = DateFormatter.localizedString(from: date,
                                                              dateStyle: .none,
                                                              timeStyle: .medium)
        
        
        if let earlyWarningDate = nextEarlyWarning {
            let timeToEarlyWarning = date.timeIntervalSince(earlyWarningDate)
            
            if timeToEarlyWarning < 1 && timeToEarlyWarning > 0 {
                trigerAlarmEarlyWarning()
            }
            
            nextAlarmLabel.textColor = (timeToEarlyWarning > 0 ) ? UIColor.red : UIColor.lightGray
            nextAlarmLabel.text = timeString(time: timeToEarlyWarning)
        }
        
        if nextAlarmDate.timeIntervalSince(date) < 1 {
            trigerAlarmSessionEnd()
            let nextSessionAlarms = calculateNextSessionAlarms(referenceDate: date, earlyWarningPeriod: earlyWarningSelection)
            nextSessionEnd = nextSessionAlarms.nextSessionEnd
            nextEarlyWarning = nextSessionAlarms.earlyWarning
        }
        
        sessionEndTimeLabel.text = DateFormatter.localizedString(from: nextAlarmDate,
                                                                 dateStyle: .none,
                                                                 timeStyle: .medium)
    }
    
    
    //MARK: - Sound warnings
    func trigerAlarmEarlyWarning() {
//        AudioServicesPlayAlertSound(SystemSoundID(1312))
//
//        do {
//            audioPlayer = try AVAudioPlayer(contentsOf: URL(fileURLWithPath: soundPath2!))
//        } catch {
//
//        }
//
//        audioPlayer.play()
        
        AudioServicesPlaySystemSound(SystemSoundID(1312))
        
        AudioServicesPlayAlertSound(SystemSoundID(kSystemSoundID_Vibrate))
    }
    
    func trigerAlarmSessionEnd() {
        //AudioServicesPlayAlertSound(SystemSoundID(1151))
        AudioServicesPlaySystemSound(SystemSoundID(1151))
//
//        do {
//            audioPlayer = try AVAudioPlayer(contentsOf: URL(fileURLWithPath: soundPath1!))
//        } catch {
//
//        }
//
//        audioPlayer.play()
        AudioServicesPlayAlertSound(SystemSoundID(kSystemSoundID_Vibrate))
    }
    
    
    //MARK: - Local notifications
    
    func scheduleLocalNotifications(dates: [Date]) {
        let content = UNMutableNotificationContent()
        content.title = "Session ends (early alert)"
        
        print("Add \(dates.count) notifications")
        
        dates.forEach { (date) in
            content.body = "Session: \(formatedDateString(date: date)) | Get the cars out of the track"
            content.sound = UNNotificationSound.default
            
            let dateComponents = calendar.dateComponents([.year, .month, .day, .hour, .minute, .second], from: date)
            let trigger = UNCalendarNotificationTrigger(dateMatching: dateComponents, repeats: false)
            let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: trigger)
            
            notificationCenter.add(request) { (error) in
                if let error = error {
                    print("Error \(error.localizedDescription)")
                } else {
                    print("Add: \(date)")
                }
            }
        }
    }
    
    func scheduleLocalNotification(date: Date) {
        let content = UNMutableNotificationContent()
        content.title = "Warning"
        content.body = "Session ends early warning"
        content.sound = UNNotificationSound.default
        
        let dateComponents = calendar.dateComponents([.year, .month, .day, .hour, .minute, .second], from: date)
        let trigger = UNCalendarNotificationTrigger(dateMatching: dateComponents, repeats: false)
        
        let identifier = "Local Notification"
        let request = UNNotificationRequest(identifier: identifier, content: content, trigger: trigger)
        
        notificationCenter.add(request) { (error) in
            if let error = error {
                print("Error \(error.localizedDescription)")
            }
        }
    }
    
    func removeAllNotifications() {
        notificationCenter.removeAllPendingNotificationRequests()
    }
}

extension PlanningViewController: UIPickerViewDelegate, UIPickerViewDataSource {
    func numberOfComponents(in pickerView: UIPickerView) -> Int {
        return 1
    }
    
    func pickerView(_ pickerView: UIPickerView, numberOfRowsInComponent component: Int) -> Int {
        switch pickerView {
        case sessionsCountPicker:
            return Constants.sessionsMax
            
        case groupsCountPicker:
            return Constants.groupsMax
        
        case earlyNotification:
            return Constants.notificationAdvanceMax
            
        default:
            return 0
        }
    }
    
    // The data to return fopr the row and component (column) that's being passed in
    func pickerView(_ pickerView: UIPickerView, titleForRow row: Int, forComponent component: Int) -> String? {
        switch pickerView {
        case sessionsCountPicker:
            return String("\(row + 1)")
            
        case groupsCountPicker:
            return String("\(row + 1)")
        
        case earlyNotification:
            return String("\(row + 1) min")
        default:
            return "--"
        }
    }
    
    func pickerView(_ pickerView: UIPickerView, didSelectRow row: Int, inComponent component: Int) {
        switch pickerView {
        case sessionsCountPicker: break
            
        case groupsCountPicker: break
            
        case earlyNotification: break
            
        default:
            break
        }
        
        updateDataModel()
        collectionView.reloadData()
        
        collectionView.isScrollEnabled = true
        
    }
}

extension PlanningViewController: UICollectionViewDelegate, UICollectionViewDataSource {
    
    func numberOfSections(in collectionView: UICollectionView) -> Int {
        return sessionsCount
    }
    
    func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
        return groupsCount
    }
    
    func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
        let cell = collectionView.dequeueReusableCell(withReuseIdentifier: "timeCell", for: indexPath) as! TimeCollectionViewCell
        let index = indexPath.section * groupsCount + indexPath.row
        
        if index < sessions.count && index >= 0 {
            let date = sessions[index]
            cell.label.text = formatedDateString(date: date)
        }
        
        
        
        return cell
    }
    
}
