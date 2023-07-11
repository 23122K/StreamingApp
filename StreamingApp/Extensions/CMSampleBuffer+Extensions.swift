//
//  CMSampleBuffer+Extensions.swift
//  StreamingApp
//
//  Created by Patryk Maciąg on 11/07/2023.
//

import VideoToolbox

extension CMSampleBuffer {
    var isIFrame: Bool {
        let attachments = CMSampleBufferGetSampleAttachmentsArray(self, createIfNecessary: true) as? [[CFString: Any]]
        
        /*
         I-Frame's are synchronous, so we might encounter two scenarios when parsing CMSampleBufferGetSampleAttachmentsArray
         1.Key exist and has a value of:
            true    => Not an I-Frame
            false   => I-Frame
         2.Key does not exist => I-Frame
        */
        
        let keyExists = (attachments?.first?[kCMSampleAttachmentKey_NotSync] as? Bool) ?? false
        
        return !keyExists
    }
}

