//
//  AWSManager.swift
//  Smilables
//
//  Created by @karthi on 23/02/22.
//

import Foundation
import AWSS3
import AWSCognito
import AWSCore
import AVFoundation

enum ContentType: String {
    case image = "image/jpeg"
    case video = "movie/mov"
}

struct AWSSuccessResponse {
    let urlString:String
    let keyName:String
}

typealias progressBlock = (_ progress: Double) -> Void
typealias completionBlock = (_ response: AWSSuccessResponse?, _ error: Error?) -> Void

class AWSManager {
    
    static let shared = AWSManager()
    
    public lazy var baseS3BucketURL: URL? = {
        let url = AWSS3.default().configuration.endpoint.url
        return url
    }()
    
    class func initialize() {
        
        let credentialsProvider = AWSCognitoCredentialsProvider(regionType:.USWest1,
                                                                identityPoolId:AWSConstants.CONGNITO_POOL_IDENTITY)
        let configuration = AWSServiceConfiguration(region:.USWest1, credentialsProvider:credentialsProvider)
        AWSServiceManager.default().defaultServiceConfiguration = configuration
        
    }
    
    
    
    // Upload image using UIImage object
    func uploadImage(image: UIImage,success: @escaping (String) -> Void, onFailure failure: @escaping (Error) -> Void) {
        
        guard let imageData = image.jpegData(compressionQuality: 1.0) else {
            let error = NSError(domain:"", code:402, userInfo:[NSLocalizedDescriptionKey: "invalid image"])
            failure(error)
            return
        }
        let fileName: String = ProcessInfo.processInfo.globallyUniqueString + (".jpeg")
        
        let getPreSignedURLRequest = AWSS3GetPreSignedURLRequest()
        getPreSignedURLRequest.bucket =  AWSConstants.S3_INSOURCE_IMAGE_BUCKET_NAME
        getPreSignedURLRequest.key = fileName
        getPreSignedURLRequest.httpMethod = .PUT
        getPreSignedURLRequest.expires = Date(timeIntervalSinceNow: 3600)

        //Important: set contentType for a PUT request.
        let fileContentTypeStr = ContentType.image.rawValue
        getPreSignedURLRequest.contentType = fileContentTypeStr

        AWSS3PreSignedURLBuilder.default().getPreSignedURL(getPreSignedURLRequest).continueWith { (task:AWSTask<NSURL>) -> Any? in
            if let error = task.error {
                print("Error: \(error)")
                failure(error)
                return nil
            }

            let presignedURL = task.result
            let preSignedURLStr = presignedURL?.absoluteString
            print("Upload presignedURL is: \(String(describing: preSignedURLStr))")
            let url = URL(string: preSignedURLStr!)
            var request = URLRequest(url:url!)
            request.cachePolicy = .reloadIgnoringLocalCacheData
            request.httpMethod = "PUT"
            request.setValue(fileContentTypeStr, forHTTPHeaderField: "Content-Type")
            
            let uploadTask:URLSessionTask = URLSession.shared.uploadTask(with: request, from: imageData) { data, response, error in
                
                if let error = error {
                    failure(error)
                }
                
                if let httpStatus = response as? HTTPURLResponse, httpStatus.statusCode == 200 {
                    success(fileName)
                }
            }

            uploadTask.resume()
            
            _ = uploadTask.progress.observe(\.fractionCompleted) { progress, _ in
                print("progress: ", progress.fractionCompleted)
            }

            return nil
        }
    }
    
    // Upload video from local path url
    func uploadVideo(videoData: Data,success: @escaping (String) -> Void, onFailure failure: @escaping (Error) -> Void) {
        
        let fileName = self.getUniqueFileName()
        let getPreSignedURLRequest = AWSS3GetPreSignedURLRequest()
        getPreSignedURLRequest.bucket =  AWSConstants.S3_INSOURCE_VIDEO_BUCKET_NAME
        getPreSignedURLRequest.key = fileName
        getPreSignedURLRequest.httpMethod = .PUT
        getPreSignedURLRequest.expires = Date(timeIntervalSinceNow: 3600)

        //Important: set contentType for a PUT request.
        let fileContentTypeStr = ContentType.video.rawValue
        getPreSignedURLRequest.contentType = fileContentTypeStr
        AWSS3PreSignedURLBuilder.default().getPreSignedURL(getPreSignedURLRequest).continueWith { (task:AWSTask<NSURL>) -> Any? in
            if let error = task.error {
                print("Error: \(error)")
                failure(error)
                return nil
            }
            let presignedURL = task.result
            let preSignedURLStr = presignedURL?.absoluteString
            print("Upload presignedURL is: \(String(describing: preSignedURLStr))")
            let url = URL(string: preSignedURLStr!)
            var request = URLRequest(url:url!)
            request.cachePolicy = .reloadIgnoringLocalCacheData
            request.httpMethod = "PUT"
            request.setValue(fileContentTypeStr, forHTTPHeaderField: "Content-Type")
            let uploadTask:URLSessionTask = URLSession.shared.uploadTask(with: request, from: videoData) { data, response, error in
                if let error = error {
                    failure(error)
                }
                if let httpStatus = response as? HTTPURLResponse, httpStatus.statusCode == 200 {
                    success(fileName)
                }
            }
            uploadTask.resume()
            _ = uploadTask.progress.observe(\.fractionCompleted) { progress, _ in
                print("progress: ", progress.fractionCompleted)
            }
            return nil
        }
    }
    
    // Get unique file name
    func getUniqueFileName() -> String {
        let strExt: String = ".MOV"
        return (ProcessInfo.processInfo.globallyUniqueString + (strExt))
    }
    
    class func getCloundFrontURL(_ keyName:String) -> String {
        if keyName.contains(".jpeg") {
            let str = AWSConstants.IMAGES_INSOURCE_CLOUD_FRONT + keyName
            print(str)
            return str
        } else {
            let str = AWSConstants.VIDEOS_INSOURCE_CLOUD_FRONT + keyName
            print(str)
            return str
        }
    }
    
    class func getThumbnailImage(keyName: String,completion:@escaping ((_ url: URL) -> Void)) {
        let videoURL = keyName.dropLast(4)
        let ext = "-00001.png"
        let imgURL = AWSConstants.VIDEOS_THUMBNAIL_CLOUD_FRONT + videoURL + ext
        if let imageURL = URL(string: imgURL) {
            completion(imageURL)
        }
    }
    
}


