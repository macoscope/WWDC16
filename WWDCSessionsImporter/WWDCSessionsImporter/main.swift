import Foundation

let RepositoryName = "macoscope/WWDC16"
let GitHubAccessToken = ""


enum Platform: String {
    case iOS
    case macOS
    case tvOS
    case watchOS
}


enum Track: String {
    case AppFrameworks = "App Frameworks"
    case DeveloperTools = "Developer Tools"
    case Distribution = "Distribution"
    case SystemFrameworks = "System Frameworks"
    case Media = "Media"
    case Design = "Design"
    case Featured = "Featured"
    case GraphicsAndGames = "Graphics and Games"
}


struct Video {
    let id: String
    let title: String
    let description: String
    let focus: [Platform]
    let track: Track
    let year: Int

    init(dictionary: [String: AnyObject]) {

        let parser = Parser(dictionary: dictionary)

        do {
            self.id = try parser.fetch("id")
            self.title = try parser.fetch("title")
            self.description = try parser.fetch("description")
            self.focus = try parser.fetchArray("focus", transformation: { (focusString: String) in
                return Platform.init(rawValue: focusString)
            })
            self.track = try parser.fetch("track", transformation: { (trackString: String) in
                return Track.init(rawValue: trackString)
            })
            self.year = try parser.fetch("year")
        } catch let e {
            print(e)
            fatalError("Video cannot be initialised using provided dictionary")
        }

    }
}


struct JSONLoaderError: ErrorType {
    let message: String
}


struct JSONLoader {
    let URL: NSURL

    init() {
        guard let URL = NSBundle.mainBundle().URLForResource("sessions", withExtension: "json") else {
            print("Sessions.json file is missing")
            exit(1)
        }
        self.init(URL: URL)
    }

    init(URL: NSURL) {
        self.URL = URL
    }

    func loadJSON() throws -> [String: AnyObject]? {
        guard let data = NSData.init(contentsOfURL: self.URL) else {
            print("Cannot read data from file at \(URL.absoluteString) path")
            exit(1)
        }

        do {
            let data = try NSJSONSerialization.JSONObjectWithData(data, options: NSJSONReadingOptions.init(rawValue: 0))
            guard let dictionary = data as? [String: AnyObject] else {
                throw JSONLoaderError(message: "Root object in a JSON file isn't an instance of dictionary")
            }

            return dictionary;
        } catch _ {
            throw JSONLoaderError(message: "JSON deserialization error")
        }
    }

}

struct SessionsImporter {
    let loader = JSONLoader()

    func importSessions() -> [Video]? {

        do {
            let JSON = try self.loader.loadJSON()
            guard let sessionsJSON = JSON?["sessions"] else {
                return nil
            }

            guard let videosJSONArray = sessionsJSON as? [[String: AnyObject]] else {
                return nil
            }

            var videos = [Video]()
            for JSON in videosJSONArray {
                let video = Video(dictionary: JSON)
                videos.append(video)
            }

            return videos

        } catch {
            return nil
        }

    }

}


struct ParserError: ErrorType {
    let message: String
}


struct Parser {
    let dictionary: [String: AnyObject]

    init(dictionary: [String: AnyObject]) {
        self.dictionary = dictionary
    }

    func fetch<T>(key: String) throws -> T {
        guard let fetched = dictionary[key] else {
            throw ParserError(message: "The key \"\(key)\" was not found.")
        }

        guard let casted = fetched as? T else {
            throw ParserError(message: "The key \"\(key)\" was not the right type. It had value \"\(fetched).\"")
        }
        return casted
    }

    func fetch<T, U>(key: String, transformation: T -> U?) throws -> U {
        let fetched: T = try fetch(key)
        guard let transformed = transformation(fetched) else {
            throw ParserError(message: "The value \"\(fetched)\" at key \"\(key)\" could not be transformed.")
        }
        return transformed
    }

    func fetchArray<T, U>(key: String, transformation: T -> U?) throws -> [U] {
        let fetched: [T] = try fetch(key)
        return fetched.flatMap(transformation)
    }

}



struct CreateGitHubIssueURLRequestCreator {
    let video: Video

    init(video: Video) {
        self.video = video
    }

    func makeURLRequest() -> NSURLRequest {
        let URLRequest = NSMutableURLRequest()
        URLRequest.HTTPMethod = "POST"
        URLRequest.URL = makeURL()
        URLRequest.HTTPBody = makeBody()
        return URLRequest
    }
    
    private func makeURL() -> NSURL {
        let URLComponents = NSURLComponents(string: "https://api.github.com/repos/\(RepositoryName)/issues")!
        URLComponents.queryItems = [NSURLQueryItem.init(name: "access_token", value: GitHubAccessToken)]
        return URLComponents.URL!
    }

    private func makeBody() -> NSData {
        let bodyDictionary = [
            "title": "\(self.video.id): \(self.video.title)",
            "body": makeDescription(),
            "labels": makeLabels(),
        ]

        do {
            return try NSJSONSerialization.dataWithJSONObject(bodyDictionary, options: NSJSONWritingOptions.init(rawValue: 0))
        } catch let error {
            print(error)
            fatalError()
        }
    }

    private func makeLabels() -> [String] {
        var labels = [String]()
        labels.append(self.video.track.rawValue)
        labels.appendContentsOf(self.video.focus.map({ focus in
            return focus.rawValue
        }))
        return labels
    }

    private func makeDescription() -> String {
        let base = "https://developer.apple.com/videos/play/wwdc2016/\(self.video.id)\n\n\(self.video.description)\n\n"
        
        let labels = makeLabels()
        var labelsString = "Keywords: "
        for label in labels {
            labelsString = labelsString + label;
            if (labels.last != label) {
                labelsString = labelsString + ", "
            } else {
                labelsString = labelsString + "."
            }
        }
        
        return base + labelsString
    }

}


let sessionsImporter = SessionsImporter()
guard let videos = sessionsImporter.importSessions() else {
    print("Can't import videos")
    exit(1)
}

let sortedVideos = videos.sort({ (l, r) -> Bool in
    return l.id > r.id
})



let group = dispatch_group_create()

for video in sortedVideos {
    guard video.year == 2016 else {
        continue
    }
    dispatch_group_enter(group)
    let requestCreator = CreateGitHubIssueURLRequestCreator(video: video)
    
    let task = NSURLSession.sharedSession().dataTaskWithRequest(requestCreator.makeURLRequest(), completionHandler: { (data, response, error) in
        if (response as? NSHTTPURLResponse)?.statusCode != 201 {
            print("Error when creating issue for session named '\(video.title)': \(error?.localizedDescription ?? "")")
        }
        dispatch_group_leave(group)
    })
    task.resume()
}

dispatch_group_wait(group, DISPATCH_TIME_FOREVER)


print("Finished")
