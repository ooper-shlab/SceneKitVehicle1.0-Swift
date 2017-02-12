//
//  OverlayScene.swift
//  SceneKitVehicle
//
//  Translated by OOPer in cooperation with shlab.jp, on 2014/08/17.
//
//
/*
 Copyright (C) 2014 Apple Inc. All Rights Reserved.
 See LICENSE.txt for this sample’s licensing information

 Abstract:

  A SpriteKit scene used as an overlay.

 */

import SpriteKit

@objc(AAPLOverlayScene)
class OverlayScene: SKScene {
    
    private(set) var speedNeedle: SKNode!
    
    
    override init(size: CGSize) {
        super.init(size: size)
        //setup the overlay scene
        anchorPoint = CGPoint(x: 0.5, y: 0.5)
        
        //automatically resize to fill the viewport
        scaleMode = .resizeFill
        
        //make UI larger on iPads
        let iPad = UIDevice.current.userInterfaceIdiom == .pad
        let scale: CGFloat = iPad ? 1.5 : 1
        
        //add the speed gauge
        let myImage = SKSpriteNode(imageNamed: "speedGauge.png")
        myImage.anchorPoint = CGPoint(x: 0.5, y: 0)
        myImage.position = CGPoint(x: size.width * 0.33, y: -size.height * 0.5)
        myImage.xScale = 0.8 * scale
        myImage.yScale = 0.8 * scale
        addChild(myImage)
        
        //add the needed
        let needleHandle = SKNode()
        let needle = SKSpriteNode(imageNamed: "needle.png")
        needleHandle.position = CGPoint(x: 0, y: 16)
        needle.anchorPoint = CGPoint(x: 0.5, y: 0)
        needle.xScale = 0.7
        needle.yScale = 0.7
        needle.zRotation = CGFloat(π_2)
        needleHandle.addChild(needle)
        myImage.addChild(needleHandle)
        
        speedNeedle = needleHandle
        
        //add the camera button
        let cameraImage = SKSpriteNode(imageNamed: "video_camera.png")
        cameraImage.position = CGPoint(x: -size.width * 0.4, y: -size.height * 0.4)
        cameraImage.name = "camera"
        cameraImage.xScale = 0.6 * scale
        cameraImage.yScale = 0.6 * scale
        addChild(cameraImage)
    }
    required init?(coder aDecoder: NSCoder) {
        super.init(coder: aDecoder)
    }
    
}
