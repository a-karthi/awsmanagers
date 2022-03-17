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
    
    func preSignedURLUpload(_ data: Data,_ fileName: String,_ contentType:ContentType,onSuccess success: @escaping (String) -> Void) {
        let getPreSignedURLRequest = AWSS3GetPreSignedURLRequest()
        getPreSignedURLRequest.bucket = contentType == .image ? AWSConstants.S3_INSOURCE_IMAGE_BUCKET_NAME : AWSConstants.S3_INSOURCE_VIDEO_BUCKET_NAME
        getPreSignedURLRequest.key = fileName
        getPreSignedURLRequest.httpMethod = .PUT
        getPreSignedURLRequest.expires = Date(timeIntervalSinceNow: 3600)

        //Important: set contentType for a PUT request.
        let fileContentTypeStr = contentType.rawValue
        getPreSignedURLRequest.contentType = fileContentTypeStr

        AWSS3PreSignedURLBuilder.default().getPreSignedURL(getPreSignedURLRequest).continueWith { (task:AWSTask<NSURL>) -> Any? in
            if let error = task.error {
                print("Error: \(error)")
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
            
            let uploadTask:URLSessionTask = URLSession.shared.uploadTask(with: request, from: data) { data, response, error in
                
                guard _ = data, error == nil else {
                    print(error?.localizedDescription ?? "")
                    return
                }

                if let httpStatus = response as? HTTPURLResponse, httpStatus.statusCode == 200 {
                    success(fileName)
                }
            }

            uploadTask.resume()

            return nil
        }
    }
    
    
    
    // Upload image using UIImage object
    func uploadImage(image: UIImage, progress: progressBlock?, completion: completionBlock?) {
        
        guard let imageData = image.jpegData(compressionQuality: 1.0) else {
            let error = NSError(domain:"", code:402, userInfo:[NSLocalizedDescriptionKey: "invalid image"])
            completion?(nil, error)
            return
        }
        
        let tmpPath = NSTemporaryDirectory() as String
        let fileName: String = ProcessInfo.processInfo.globallyUniqueString + (".jpeg")
        let filePath = tmpPath + "/" + fileName
        let fileUrl = URL(fileURLWithPath: filePath)
        
        do {
            try imageData.write(to: fileUrl)
            self.uploadImage(fileUrl: fileUrl, fileName: fileName, progress: progress, completion: completion)
        } catch {
            let error = NSError(domain:"", code:402, userInfo:[NSLocalizedDescriptionKey: "invalid image"])
            completion?(nil, error)
        }
    }
    
    // Upload video from local path url
    func uploadVideo(videoUrl: URL, progress: progressBlock?, completion: completionBlock?) {
        let fileName = self.getUniqueFileName(fileUrl: videoUrl)
        self.uploadVideo(fileUrl: videoUrl, fileName: fileName, progress: progress, completion: completion)
    }
    
    // Get unique file name
    func getUniqueFileName(fileUrl: URL) -> String {
        let strExt: String = "." + (URL(fileURLWithPath: fileUrl.absoluteString).pathExtension)
        return (ProcessInfo.processInfo.globallyUniqueString + (strExt))
    }
    
    //MARK:- AWS file upload
    // fileUrl :  file local path url
    // fileName : name of file, like "myimage.jpeg" "video.mov"
    // contenType: file MIME type
    // progress: file upload progress, value from 0 to 1, 1 for 100% complete
    // completion: completion block when uplaoding is finish, you will get S3 url of upload file here
    private func uploadImage(fileUrl: URL, fileName: String, progress: progressBlock?, completion: completionBlock?) {
        
        let bucketName = AWSConstants.S3_INSOURCE_IMAGE_BUCKET_NAME
        
        // Upload progress block
        let expression = AWSS3TransferUtilityUploadExpression()
        expression.progressBlock = {(task, awsProgress) in
            guard let uploadProgress = progress else { return }
            DispatchQueue.main.async {
                uploadProgress(awsProgress.fractionCompleted)
            }
        }
        // Completion block
        var completionHandler: AWSS3TransferUtilityUploadCompletionHandlerBlock?
        completionHandler = { (task, error) -> Void in
            DispatchQueue.main.async(execute: {
                if error == nil {
                    let url = AWSS3.default().configuration.endpoint.url
                    let publicURL = url?.appendingPathComponent(bucketName).appendingPathComponent(fileName)
                    print("Uploaded to:\(String(describing: publicURL))")
                    if let completionBlock = completion {
                        let res = AWSSuccessResponse(urlString: publicURL?.absoluteString ?? "", keyName: fileName)
                        completionBlock(res, nil)
                    }
                } else {
                    if let completionBlock = completion {
                        completionBlock(nil, error)
                    }
                }
            })
        }
        
        // Start uploading using AWSS3TransferUtility
        let awsTransferUtility = AWSS3TransferUtility.default()
        awsTransferUtility.uploadFile(fileUrl, bucket: bucketName, key: fileName,contentType:ContentType.image.rawValue, expression: expression, completionHandler: completionHandler).continueWith { (task) -> Any? in
            if let error = task.error {
                print("error is: \(error.localizedDescription)")
            }
            if let _ = task.result {
                // your uploadTask
            }
            return nil
        }
    }
    
    private func uploadVideo(fileUrl: URL, fileName: String, progress: progressBlock?, completion: completionBlock?) {
        
        let bucketName = AWSConstants.S3_INSOURCE_VIDEO_BUCKET_NAME
        
        // Upload progress block
        let expression = AWSS3TransferUtilityUploadExpression()
        expression.progressBlock = {(task, awsProgress) in
            guard let uploadProgress = progress else { return }
            DispatchQueue.main.async {
                uploadProgress(awsProgress.fractionCompleted)
            }
        }
        // Completion block
        var completionHandler: AWSS3TransferUtilityUploadCompletionHandlerBlock?
        completionHandler = { (task, error) -> Void in
            DispatchQueue.main.async(execute: {
                if error == nil {
                    let url = AWSS3.default().configuration.endpoint.url
                    let publicURL = url?.appendingPathComponent(bucketName).appendingPathComponent(fileName)
                    print("Uploaded to:\(String(describing: publicURL))")
                    if let completionBlock = completion {
                        let res = AWSSuccessResponse(urlString: publicURL?.absoluteString ?? "", keyName: fileName)
                        completionBlock(res, nil)
                    }
                } else {
                    if let completionBlock = completion {
                        completionBlock(nil, error)
                    }
                }
            })
        }
        
        // Start uploading using AWSS3TransferUtility
        let awsTransferUtility = AWSS3TransferUtility.default()
        do {
            let fileData = try Data(contentsOf: fileUrl)
            awsTransferUtility.uploadData(fileData, bucket: bucketName, key: fileName, contentType: ContentType.video.rawValue, expression: expression, completionHandler: completionHandler).continueWith { (task) -> Any? in
                if let error = task.error {
                    print("error is: \(error.localizedDescription)")
                }
                if let _ = task.result {
                    // your uploadTask
                }
                return nil
            }
        } catch {
            print ("loading video file error")
        }
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
    
    class func getThumbnailImage(forUrl url: URL,completion:@escaping ((_ image: UIImage) -> Void)) {
        let asset: AVAsset = AVAsset(url: url)
        let imageGenerator = AVAssetImageGenerator(asset: asset)

        do {
            let thumbnailImage = try imageGenerator.copyCGImage(at: CMTimeMake(value: 1, timescale: 60), actualTime: nil)
            let img =  UIImage(cgImage: thumbnailImage)
            completion(img)
        } catch let error {
            print(error)
        }
    }
    
}


