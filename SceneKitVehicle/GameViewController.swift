//
//  GameViewController.swift
//  SceneKitVehicle
//
//  Translated by OOPer in cooperation with shlab.jp, on 2014/08/17.
//  Copyright (c) 2014年 Apple Inc. All rights reserved.
//
/*
 Copyright (C) 2014 Apple Inc. All Rights Reserved.
 See LICENSE.txt for this sample’s licensing information

 Abstract:

  A view controller that conforms to SCNSceneRendererDelegate and implements the game logic.

 */

import UIKit
import CoreMotion
import SpriteKit
import SceneKit
import GameController
import simd

//--Global constants
let π = M_PI
let π_2 = M_PI_2
let π_4 = M_PI_4

@objc(AAPLGameViewController)
class GameViewController: UIViewController, SCNSceneRendererDelegate {
    
    private let MAX_SPEED: CGFloat = 250
    
    //some node references for manipulation
    private var _spotLightNode: SCNNode!
    private var _cameraNode: SCNNode!          //the node that owns the camera
    private var _vehicleNode: SCNNode!
    private var _vehicle: SCNPhysicsVehicle!
    private var _reactor: SCNParticleSystem!
    
    //accelerometer
    private var _motionManager: CMMotionManager!
    private var _accelerometer = [UIAccelerationValue](count: 3, repeatedValue: 0.0)
    private var _orientation: CGFloat = 0.0
    
    //reactor's particle birth rate
    private var _reactorDefaultBirthRate: CGFloat = 0.0
    
    // steering factor
    private var _vehicleSteering: CGFloat = 0.0
    
    private func deviceName() -> String {
        struct My {
            static var deviceName: String? = nil
        }
        
        if My.deviceName == nil {
            var systemInfo = utsname()
            uname(&systemInfo)
            My.deviceName = String.fromCString(&systemInfo.machine.0)
        }
        return My.deviceName!
    }
    
    private var isHighEndDevice: Bool {
        //return YES for iPhone 5s and iPad air, NO otherwise
        return deviceName().hasPrefix("iPad4")
            || deviceName().hasPrefix("iPhone6")
        
    }
    
    private func setupEnvironment(scene: SCNScene) {
        // add an ambient light
        let ambientLight = SCNNode()
        ambientLight.light = SCNLight()
        ambientLight.light!.type = SCNLightTypeAmbient
        ambientLight.light!.color = UIColor(white: 0.3, alpha: 1.0)
        scene.rootNode.addChildNode(ambientLight)
        
        //add a key light to the scene
        let lightNode = SCNNode()
        lightNode.light = SCNLight()
        lightNode.light!.type = SCNLightTypeSpot
        if isHighEndDevice {
            lightNode.light!.castsShadow = true
        }
        lightNode.light!.color = UIColor(white: 0.8, alpha: 1.0)
        lightNode.position = SCNVector3Make(0, 80, 30)
        lightNode.rotation = SCNVector4Make(1, 0, 0, Float(-M_PI/2.8))
        lightNode.light!.spotInnerAngle = 0
        lightNode.light!.spotOuterAngle = 50
        lightNode.light!.shadowColor = SKColor.blackColor()
        lightNode.light!.zFar = 500
        lightNode.light!.zNear = 50
        scene.rootNode.addChildNode(lightNode)
        
        //keep an ivar for later manipulation
        _spotLightNode = lightNode
        
        //floor
        let floor = SCNNode()
        floor.geometry = SCNFloor() as SCNGeometry
        floor.geometry!.firstMaterial!.diffuse.contents = "wood.png"
        floor.geometry!.firstMaterial!.diffuse.contentsTransform = SCNMatrix4MakeScale(2, 2, 1) //scale the wood texture
        floor.geometry!.firstMaterial!.locksAmbientWithDiffuse = true
        if isHighEndDevice {
            (floor.geometry as! SCNFloor).reflectionFalloffEnd = 10
        }
        
        let staticBody = SCNPhysicsBody.staticBody()
        floor.physicsBody = staticBody
        scene.rootNode.addChildNode(floor)
    }
    
    private func addTrainToScene(scene: SCNScene, atPosition pos: SCNVector3) {
        let trainScene = SCNScene(named: "train_flat")!
        
        //physicalize the train with simple boxes
        for node in trainScene.rootNode.childNodes as [SCNNode] {
            //let node = obj as! SCNNode
            if node.geometry != nil {
                node.position = SCNVector3Make(node.position.x + pos.x, node.position.y + pos.y, node.position.z + pos.z)
                
                var min = SCNVector3Zero, max = SCNVector3Zero
                node.getBoundingBoxMin(&min, max: &max)
                
                let body = SCNPhysicsBody.dynamicBody()
                let boxShape = SCNBox(width:CGFloat(max.x - min.x), height:CGFloat(max.y - min.y), length:CGFloat(max.z - min.z), chamferRadius:0.0)
                body.physicsShape = SCNPhysicsShape(geometry: boxShape, options:nil)
                
                node.pivot = SCNMatrix4MakeTranslation(0, -min.y, 0)
                node.physicsBody = body
                scene.rootNode.addChildNode(node)
            }
        }
        
        //add smoke
        let smokeHandle = scene.rootNode.childNodeWithName("Smoke", recursively: true)
        smokeHandle!.addParticleSystem(SCNParticleSystem(named: "smoke", inDirectory: nil)!)
        
        //add physics constraints between engine and wagons
        let engineCar = scene.rootNode.childNodeWithName("EngineCar", recursively: false)
        let wagon1 = scene.rootNode.childNodeWithName("Wagon1", recursively: false)
        let wagon2 = scene.rootNode.childNodeWithName("Wagon2", recursively: false)
        
        var min = SCNVector3Zero, max = SCNVector3Zero
        engineCar!.getBoundingBoxMin(&min, max: &max)
        
        var wmin = SCNVector3Zero, wmax = SCNVector3Zero
        wagon1!.getBoundingBoxMin(&wmin, max: &wmax)
        
        // Tie EngineCar & Wagon1
        var joint = SCNPhysicsBallSocketJoint(bodyA: engineCar!.physicsBody!, anchorA: SCNVector3Make(max.x, min.y, 0),
            bodyB: wagon1!.physicsBody!, anchorB: SCNVector3Make(wmin.x, wmin.y, 0))
        scene.physicsWorld.addBehavior(joint)
        
        // Wagon1 & Wagon2
        joint = SCNPhysicsBallSocketJoint(bodyA: wagon1!.physicsBody!, anchorA: SCNVector3Make(wmax.x + 0.1, wmin.y, 0),
            bodyB: wagon2!.physicsBody!, anchorB: SCNVector3Make(wmin.x - 0.1, wmin.y, 0))
        scene.physicsWorld.addBehavior(joint)
    }
    
    
    private func addWoodenBlockToScene(scene:SCNScene, withImageNamed imageName:NSString, atPosition position:SCNVector3) {
        //create a new node
        let block = SCNNode()
        
        //place it
        block.position = position
        
        //attach a box of 5x5x5
        block.geometry = SCNBox(width: 5, height: 5, length: 5, chamferRadius: 0)
        
        //use the specified images named as the texture
        block.geometry!.firstMaterial!.diffuse.contents = imageName
        
        //turn on mipmapping
        block.geometry!.firstMaterial!.diffuse.mipFilter = .Linear
        
        //make it physically based
        block.physicsBody = SCNPhysicsBody.dynamicBody()
        
        //add to the scene
        scene.rootNode.addChildNode(block)
    }
    
    private func setupSceneElements(scene: SCNScene) {
        // add a train
        addTrainToScene(scene, atPosition: SCNVector3Make(-5, 20, -40))
        
        // add wooden blocks
        addWoodenBlockToScene(scene, withImageNamed: "WoodCubeA.jpg", atPosition: SCNVector3Make(-10, 15, 10))
        addWoodenBlockToScene(scene, withImageNamed: "WoodCubeB.jpg", atPosition: SCNVector3Make(-9, 10, 10))
        addWoodenBlockToScene(scene, withImageNamed: "WoodCubeC.jpg", atPosition: SCNVector3Make(20, 15, -11))
        addWoodenBlockToScene(scene, withImageNamed: "WoodCubeA.jpg", atPosition: SCNVector3Make(25 , 5, -20))
        
        // add walls
        let wall = SCNNode(geometry: SCNBox(width: 400, height: 100, length: 4, chamferRadius: 0))
        wall.geometry!.firstMaterial!.diffuse.contents = "wall.jpg"
        wall.geometry!.firstMaterial!.diffuse.contentsTransform = SCNMatrix4Mult(SCNMatrix4MakeScale(24, 2, 1), SCNMatrix4MakeTranslation(0, 1, 0))
        wall.geometry!.firstMaterial!.diffuse.wrapS = .Repeat
        wall.geometry!.firstMaterial!.diffuse.wrapT = .Mirror
        wall.geometry!.firstMaterial!.doubleSided = false
        wall.castsShadow = false
        wall.geometry!.firstMaterial!.locksAmbientWithDiffuse = true
        
        wall.position = SCNVector3Make(0, 50, -92)
        wall.physicsBody = SCNPhysicsBody.staticBody()
        scene.rootNode.addChildNode(wall)
        
        let wallC = wall.clone() as SCNNode
        wallC.position = SCNVector3Make(-202, 50, 0)
        wallC.rotation = SCNVector4Make(0, 1, 0, Float(π_2))
        scene.rootNode.addChildNode(wallC)
        
        let wallD = wall.clone() as SCNNode
        wallD.position = SCNVector3Make(202, 50, 0)
        wallD.rotation = SCNVector4Make(0, 1, 0, Float(-π_2))
        scene.rootNode.addChildNode(wallD)
        
        let backWall = SCNNode(geometry: SCNPlane(width: 400, height: 100))
        backWall.geometry!.firstMaterial = wall.geometry!.firstMaterial
        backWall.position = SCNVector3Make(0, 50, 200)
        backWall.rotation = SCNVector4Make(0, 1, 0, Float(π))
        backWall.castsShadow = false
        backWall.physicsBody = SCNPhysicsBody.staticBody()
        scene.rootNode.addChildNode(backWall)
        
        // add ceil
        let ceilNode = SCNNode(geometry: SCNPlane(width: 400, height: 400))
        ceilNode.position = SCNVector3Make(0, 100, 0)
        ceilNode.rotation = SCNVector4Make(1, 0, 0, Float(π_2))
        ceilNode.geometry!.firstMaterial!.doubleSided = false
        ceilNode.castsShadow = false
        ceilNode.geometry!.firstMaterial!.locksAmbientWithDiffuse = true
        scene.rootNode.addChildNode(ceilNode)
        
        //add more block
        for _ in 0 ..< 4 {
            addWoodenBlockToScene(scene, withImageNamed: "WoodCubeA.jpg", atPosition: SCNVector3Make(Float(rand() % 60 - 30), 20, Float(rand() % 40 - 20)))
            addWoodenBlockToScene(scene, withImageNamed: "WoodCubeB.jpg", atPosition: SCNVector3Make(Float(rand() % 60 - 30), 20, Float(rand() % 40 - 20)))
            addWoodenBlockToScene(scene, withImageNamed: "WoodCubeC.jpg", atPosition: SCNVector3Make(Float(rand() % 60 - 30), 20, Float(rand() % 40 - 20)))
        }
        
        // add cartoon book
        let block = SCNNode()
        block.position = SCNVector3Make(20, 10, -16)
        block.rotation = SCNVector4Make(0, 1, 0, Float(-π_4))
        block.geometry = SCNBox(width: 22, height: 0.2, length: 34, chamferRadius: 0)
        let frontMat = SCNMaterial()
        frontMat.locksAmbientWithDiffuse = true
        frontMat.diffuse.contents = "book_front.jpg"
        frontMat.diffuse.mipFilter = .Linear
        let backMat = SCNMaterial()
        backMat.locksAmbientWithDiffuse = true
        backMat.diffuse.contents = "book_back.jpg"
        backMat.diffuse.mipFilter = .Linear
        block.geometry!.materials = [frontMat, backMat]
        block.physicsBody = SCNPhysicsBody.dynamicBody()
        scene.rootNode.addChildNode(block)
        
        // add carpet
        let rug = SCNNode()
        rug.position = SCNVector3Make(0, 0.01, 0)
        rug.rotation = SCNVector4Make(1, 0, 0, Float(π_2))
        let path = UIBezierPath(roundedRect: CGRectMake(-50, -30, 100, 50), cornerRadius: 2.5)
        path.flatness = 0.1
        rug.geometry = SCNShape(path: path, extrusionDepth: 0.05)
        rug.geometry!.firstMaterial!.locksAmbientWithDiffuse = true
        rug.geometry!.firstMaterial!.diffuse.contents = "carpet.jpg"
        scene.rootNode.addChildNode(rug)
        
        // add ball
        let ball = SCNNode()
        ball.position = SCNVector3Make(-5, 5, -18)
        ball.geometry = SCNSphere(radius: 5)
        ball.geometry!.firstMaterial!.locksAmbientWithDiffuse = true
        ball.geometry!.firstMaterial!.diffuse.contents = "ball.jpg"
        ball.geometry!.firstMaterial!.diffuse.contentsTransform = SCNMatrix4MakeScale(2, 1, 1)
        ball.geometry!.firstMaterial!.diffuse.wrapS = .Mirror
        ball.physicsBody = SCNPhysicsBody.dynamicBody()
        ball.physicsBody!.restitution = 0.9
        scene.rootNode.addChildNode(ball)
    }
    
    
    private func setupVehicle(scene: SCNScene) -> SCNNode {
        let carScene = SCNScene(named: "rc_car")!
        let chassisNode = carScene.rootNode.childNodeWithName("rccarBody", recursively: false)
        
        // setup the chassis
        chassisNode!.position = SCNVector3Make(0, 10, 30)
        chassisNode!.rotation = SCNVector4Make(0, 1, 0, Float(π))
        
        let body = SCNPhysicsBody.dynamicBody()
        body.allowsResting = false
        body.mass = 80
        body.restitution = 0.1
        body.friction = 0.5
        body.rollingFriction = 0
        
        chassisNode!.physicsBody = body
        scene.rootNode.addChildNode(chassisNode!)
        
        let pipeNode = chassisNode!.childNodeWithName("pipe", recursively: true)
        _reactor = SCNParticleSystem(named: "reactor", inDirectory: nil)
        _reactorDefaultBirthRate = _reactor.birthRate
        _reactor.birthRate = 0
        pipeNode!.addParticleSystem(_reactor)
        
        //add wheels
        let wheel0Node = chassisNode!.childNodeWithName("wheelLocator_FL", recursively: true)!
        let wheel1Node = chassisNode!.childNodeWithName("wheelLocator_FR", recursively: true)!
        let wheel2Node = chassisNode!.childNodeWithName("wheelLocator_RL", recursively: true)!
        let wheel3Node = chassisNode!.childNodeWithName("wheelLocator_RR", recursively: true)!
        
        let wheel0 = SCNPhysicsVehicleWheel(node: wheel0Node)
        let wheel1 = SCNPhysicsVehicleWheel(node: wheel1Node)
        let wheel2 = SCNPhysicsVehicleWheel(node: wheel2Node)
        let wheel3 = SCNPhysicsVehicleWheel(node: wheel3Node)
        
        var min = SCNVector3Zero, max = SCNVector3Zero
        wheel0Node.getBoundingBoxMin(&min, max: &max)
        let wheelHalfWidth = Float(0.5 * (max.x - min.x))
        
        wheel0.connectionPosition = SCNVector3FromFloat3(SCNVector3ToFloat3(wheel0Node.convertPosition(SCNVector3Zero, toNode: chassisNode)) + float3(wheelHalfWidth, 0, 0))
        wheel1.connectionPosition = SCNVector3FromFloat3(SCNVector3ToFloat3(wheel1Node.convertPosition(SCNVector3Zero, toNode: chassisNode)) - float3(wheelHalfWidth, 0, 0))
        wheel2.connectionPosition = SCNVector3FromFloat3(SCNVector3ToFloat3(wheel2Node.convertPosition(SCNVector3Zero, toNode: chassisNode)) + float3(wheelHalfWidth, 0, 0))
        wheel3.connectionPosition = SCNVector3FromFloat3(SCNVector3ToFloat3(wheel3Node.convertPosition(SCNVector3Zero, toNode: chassisNode)) - float3(wheelHalfWidth, 0, 0))
        
        // create the physics vehicle
        let vehicle = SCNPhysicsVehicle(chassisBody: chassisNode!.physicsBody!, wheels: [wheel0, wheel1, wheel2, wheel3])
        scene.physicsWorld.addBehavior(vehicle)
        
        _vehicle = vehicle
        
        return chassisNode!
    }
    
    private func setupScene() -> SCNScene {
        // create a new scene
        let scene = SCNScene()
        
        //global environment
        setupEnvironment(scene)
        
        //add elements
        setupSceneElements(scene)
        
        //setup vehicle
        _vehicleNode = setupVehicle(scene)
        
        //create a main camera
        _cameraNode = SCNNode()
        _cameraNode.camera = SCNCamera()
        _cameraNode.camera!.zFar = 500
        _cameraNode.position = SCNVector3Make(0, 60, 50)
        _cameraNode.rotation  = SCNVector4Make(1, 0, 0, -Float(π_4) * 0.75)
        scene.rootNode.addChildNode(_cameraNode)
        
        //add a secondary camera to the car
        let frontCameraNode = SCNNode()
        frontCameraNode.position = SCNVector3Make(0, 3.5, 2.5)
        frontCameraNode.rotation = SCNVector4Make(0, 1, 0, Float(π))
        frontCameraNode.camera = SCNCamera()
        frontCameraNode.camera!.xFov = 75
        frontCameraNode.camera!.zFar = 500
        
        _vehicleNode.addChildNode(frontCameraNode)
        
        return scene
    }
    
    private func setupAccelerometer() {
        //event
        _motionManager = CMMotionManager()
        
        if GCController.controllers().count == 0 && _motionManager.accelerometerAvailable {
            _motionManager.accelerometerUpdateInterval = 1/60.0
            _motionManager.startAccelerometerUpdatesToQueue(NSOperationQueue.mainQueue()) {[weak self] accelerometerData, error in
                self!.accelerometerDidChange(accelerometerData!.acceleration)
            }
        }
    }
    
    override func prefersStatusBarHidden() -> Bool {
        return true
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        UIApplication.sharedApplication().statusBarHidden = true
        
        let scnView = view as! SCNView
        
        //set the background to back
        scnView.backgroundColor = SKColor.blackColor()
        
        //setup the scene
        let scene = setupScene()
        
        //present it
        scnView.scene = scene
        
        //tweak physics
        scnView.scene!.physicsWorld.speed = 4.0
        
        //setup overlays
        scnView.overlaySKScene = OverlayScene(size: scnView.bounds.size)
        
        //setup accelerometer
        setupAccelerometer()
        
        //initial point of view
        scnView.pointOfView = _cameraNode
        
        //plug game logic
        scnView.delegate = self
        
        
        let doubleTap = UITapGestureRecognizer(target: self, action: #selector(GameViewController.handleDoubleTap(_:)))
        doubleTap.numberOfTapsRequired = 2
        doubleTap.numberOfTouchesRequired = 2
        scnView.gestureRecognizers = [doubleTap]
        
        super.viewDidLoad()
    }
    
    func handleDoubleTap(gesture: UITapGestureRecognizer) {
        let scene = setupScene()
        
        let scnView = view as! SCNView
        //present it
        scnView.scene = scene
        
        //tweak physics
        scnView.scene!.physicsWorld.speed = 4.0
        
        //initial point of view
        scnView.pointOfView = _cameraNode
        
        (scnView as! GameView).touchCount = 0
    }
    
    // game logic
    func renderer(aRenderer: SCNSceneRenderer, didSimulatePhysicsAtTime time: NSTimeInterval) {
        let defaultEngineForce: CGFloat = 300.0
        let defaultBrakingForce: CGFloat = 3.0
        let steeringClamp: CGFloat = 0.6
        let cameraDamping: CGFloat = 0.3
        
        let scnView = view as! GameView
        
        var engineForce: CGFloat = 0
        var brakingForce: CGFloat = 0
        
        let controllers = GCController.controllers()
        
        var orientation = _orientation
        
        //drive: 1 touch = accelerate, 2 touches = backward, 3 touches = brake
        if scnView.touchCount == 1 {
            engineForce = defaultEngineForce
            _reactor.birthRate = _reactorDefaultBirthRate
        } else if scnView.touchCount == 2 {
            engineForce = -defaultEngineForce
            _reactor.birthRate = 0
        } else if scnView.touchCount == 3 {
            brakingForce = 100
            _reactor.birthRate = 0
        } else {
            brakingForce = defaultBrakingForce
            _reactor.birthRate = 0
        }
        
        //controller support
        if !controllers.isEmpty {
            let controller = controllers[0] as GCController
            let pad = controller.gamepad!
            let dpad = pad.dpad
            
            struct My {
                static var orientationCum: CGFloat = 0
            }
            
            let INCR_ORIENTATION: CGFloat = 0.03
            let DECR_ORIENTATION: CGFloat = 0.8
            
            if dpad.right.pressed {
                if My.orientationCum < 0 {
                    My.orientationCum *= DECR_ORIENTATION
                }
                My.orientationCum += INCR_ORIENTATION
                if My.orientationCum > 1 {
                    My.orientationCum = 1
                }
            } else if dpad.left.pressed {
                if My.orientationCum > 0 {
                    My.orientationCum *= DECR_ORIENTATION
                }
                My.orientationCum -= INCR_ORIENTATION
                if My.orientationCum < -1 {
                    My.orientationCum = -1
                }
            } else {
                My.orientationCum *= DECR_ORIENTATION
            }
            
            orientation = My.orientationCum
            
            if pad.buttonX.pressed {
                engineForce = defaultEngineForce
                _reactor.birthRate = _reactorDefaultBirthRate
            } else if pad.buttonA.pressed {
                engineForce = -defaultEngineForce
                _reactor.birthRate = 0
            } else if pad.buttonB.pressed {
                brakingForce = 100
                _reactor.birthRate = 0
            } else {
                brakingForce = defaultBrakingForce
                _reactor.birthRate = 0
            }
        }
        
        _vehicleSteering = -orientation
        if orientation == 0 {
            _vehicleSteering *= 0.9
        }
        if _vehicleSteering < -steeringClamp {
            _vehicleSteering = -steeringClamp
        }
        if _vehicleSteering > steeringClamp {
            _vehicleSteering = steeringClamp
        }
        
        //update the vehicle steering and acceleration
        _vehicle.setSteeringAngle(_vehicleSteering, forWheelAtIndex: 0)
        _vehicle.setSteeringAngle(_vehicleSteering, forWheelAtIndex: 1)
        
        _vehicle.applyEngineForce(engineForce, forWheelAtIndex: 2)
        _vehicle.applyEngineForce(engineForce, forWheelAtIndex: 3)
        
        _vehicle.applyBrakingForce(brakingForce, forWheelAtIndex: 2)
        _vehicle.applyBrakingForce(brakingForce, forWheelAtIndex: 3)
        
        //check if the car is upside down
        reorientCarIfNeeded()
        
        // make camera follow the car node
        let car = _vehicleNode.presentationNode
        let carPos = car.position
        let targetPos = float3(carPos.x, Float(30), carPos.z + 25)
        var cameraPos = SCNVector3ToFloat3(_cameraNode.position)
        cameraPos = mix(cameraPos, targetPos, t: Float(cameraDamping))
        _cameraNode.position = SCNVector3FromFloat3(cameraPos)
        
        if scnView.inCarView {
            //move spot light in front of the camera
            let frontPosition = scnView.pointOfView!.presentationNode.convertPosition(SCNVector3Make(0, 0, -30), toNode:nil)
            _spotLightNode.position = SCNVector3Make(frontPosition.x, 80, frontPosition.z)
            _spotLightNode.rotation = SCNVector4Make(1,0,0,-Float(π/2))
        } else {
            //move spot light on top of the car
            _spotLightNode.position = SCNVector3Make(carPos.x, 80, carPos.z + 30)
            _spotLightNode.rotation = SCNVector4Make(1,0,0,-Float(π/2.8))
        }
        
        //speed gauge
        let overlayScene = scnView.overlaySKScene as! OverlayScene
        overlayScene.speedNeedle.zRotation = -(_vehicle.speedInKilometersPerHour * CGFloat(π) / MAX_SPEED)
    }
    
    private func reorientCarIfNeeded() {
        let car = _vehicleNode.presentationNode
        let carPos = car.position
        
        // make sure the car isn't upside down, and fix it if it is
        struct My {
            static var ticks = 0
            static var check = 0
            static var `try` = 0
        }
        func randf() -> Float {
            return Float(rand())
        }
        My.ticks += 1
        if My.ticks == 30 {
            let t = car.worldTransform
            if t.m22 <= 0.1 {
                My.check += 1
                if My.check == 3 {
                    My.`try` += 1
                    if My.`try` == 3 {
                        My.`try` = 0
                        
                        //hard reset
                        _vehicleNode.rotation = SCNVector4Make(0, 0, 0, 0)
                        _vehicleNode.position = SCNVector3Make(carPos.x, carPos.y + 10, carPos.z)
                        _vehicleNode.physicsBody!.resetTransform()
                    } else {
                        //try to upturn with an random impulse
                        let pos = SCNVector3Make(-10 * ((randf()/Float(RAND_MAX)) - 0.5), 0, -10 * ((randf()/Float(RAND_MAX)) - 0.5))
                        _vehicleNode.physicsBody!.applyForce(SCNVector3Make(0, 300, 0), atPosition: pos, impulse: true)
                    }
                    
                    My.check = 0
                }
            } else {
                My.check = 0
            }
            
            My.ticks = 0
        }
    }
    
    private func accelerometerDidChange(acceleration: CMAcceleration) {
        let kFilteringFactor = 0.5
        
        //Use a basic low-pass filter to only keep the gravity in the accelerometer values
        _accelerometer[0] = acceleration.x * kFilteringFactor + _accelerometer[0] * (1.0 - kFilteringFactor)
        _accelerometer[1] = acceleration.y * kFilteringFactor + _accelerometer[1] * (1.0 - kFilteringFactor)
        _accelerometer[2] = acceleration.z * kFilteringFactor + _accelerometer[2] * (1.0 - kFilteringFactor)
        
        if _accelerometer[0] > 0 {
            _orientation = CGFloat(_accelerometer[1] * 1.3)
        } else {
            _orientation = -CGFloat(_accelerometer[1] * 1.3)
        }
    }
    
    override func viewWillDisappear(animated: Bool) {
        _motionManager.stopAccelerometerUpdates()
        _motionManager = nil
    }
    
    override func shouldAutorotate() -> Bool {
        return true
    }
    
    override func supportedInterfaceOrientations() -> UIInterfaceOrientationMask {
        return UIInterfaceOrientationMask.Landscape
    }
    
    override func didReceiveMemoryWarning() {
        super.didReceiveMemoryWarning()
        // Release any cached data, images, etc that aren't in use.
    }
    
}