import XCTest
import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
@testable import ConsultantProbeCore

@MainActor final class SheetAPITests: XCTestCase {
    func testWriteUsesOnlyOneRawScoreCellAndBearerAuthorization() async throws {
        var requests: [URLRequest] = []
        let api = GoogleSheetAPI(token: { "test-token" }, transport: { request in
            requests.append(request)
            return (Data("{}".utf8), HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!)
        })
        try await api.write(fileID: ProbeRunner.testFileID, inputTab: "점수 입력 [Score Input]", value: 9_975_813)
        XCTAssertEqual(requests.count, 1)
        let request = try XCTUnwrap(requests.first)
        XCTAssertEqual(request.url?.host, "sheets.googleapis.com")
        XCTAssertEqual(request.httpMethod, "POST")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer test-token")
        let body = try XCTUnwrap(JSONSerialization.jsonObject(with: request.httpBody!) as? [String: Any])
        XCTAssertEqual(body["valueInputOption"] as? String, "RAW")
        let data = try XCTUnwrap(body["data"] as? [[String: Any]])
        XCTAssertEqual(data.count, 1)
        XCTAssertEqual(data[0]["range"] as? String, "'점수 입력 [Score Input]'!H5")
        XCTAssertEqual(data[0]["values"] as? [[Double]], [[9_975_813]])
    }
    func testWriteRejectsNonFixtureTargetsBeforeObtainingToken() async {
        var tokenCalls = 0
        let api = GoogleSheetAPI(token: { tokenCalls += 1; return "test" })
        do { try await api.write(fileID: "other", inputTab: "Score Input", value: 9_975_813); XCTFail() } catch {}
        do { try await api.write(fileID: ProbeRunner.testFileID, inputTab: "Score Input", value: 123); XCTFail() } catch {}
        XCTAssertEqual(tokenCalls, 0)
    }
    func testRateLimitIsNotAutomaticallyRetriedAndDoesNotExposeResponseBody() async {
        var calls = 0
        let api = GoogleSheetAPI(token: { "test" }, transport: { request in
            calls += 1
            return (Data("private-account-information".utf8), HTTPURLResponse(url: request.url!, statusCode: 429, httpVersion: nil, headerFields: ["Retry-After": "120"])!)
        })
        do { _ = try await api.metadata(fileID: "test"); XCTFail() }
        catch let error as SheetHTTPError {
            XCTAssertEqual(error.status, 429); XCTAssertEqual(error.retryAfter, "120")
            XCTAssertFalse(error.localizedDescription.contains("private-account-information"))
        } catch { XCTFail("Unexpected error type") }
        XCTAssertEqual(calls, 1)
    }
    func testFileJournalSurvivesNewStoreAndMalformedJournalDoesNotDisappear() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let url = folder.appendingPathComponent("journal.json")
        let first = FileProbeJournal(url: url)
        let baseline = ProbeSnapshot(input: 0, decoded: 0, rating: 0, priority: -0.01822)
        try first.save(ProbeJournal(fileID: ProbeRunner.testFileID, inputTab: "점수 입력 [Score Input]", baseline: baseline))
        let second = FileProbeJournal(url: url)
        XCTAssertEqual(try second.load()?.baseline, baseline)
        try Data("broken".utf8).write(to: url)
        XCTAssertThrowsError(try second.load())
        XCTAssertTrue(FileManager.default.fileExists(atPath: url.path))
    }
    func testSnapshotUsesEvaluatedChartIdentityAndRawScore() async throws {
        var requests: [URLRequest] = []
        let api = GoogleSheetAPI(token: { "test" }, transport: { request in
            requests.append(request)
            let query = URLComponents(url: request.url!, resolvingAgainstBaseURL: false)!.queryItems!
            let json: String
            if query.contains(where: { $0.name == "valueRenderOption" && $0.value == "FORMULA" }) {
                // Reproduce the live formula-mode response: spill-derived title is empty.
                json = request.url!.path.hasSuffix("!H5") ? ##"{"values":[[0]]}"## : ##"{"values":[["=ARRAYFORMULA()","","","",0,0,0,0]]}"##
            } else if query.filter({ $0.name == "ranges" }).count == 3 {
                json = ##"{"valueRanges":[{"values":[["Sayonara Hatsukoi [PST]","","Sayonara Hatsukoi","PST"]]},{"values":[[0]]},{"values":[[0,0,0,0,0,0,0,0,0,-0.01822]]}]}"##
            } else {
                json = ##"{"valueRanges":[{"values":[[0]]},{"values":[[0,0,0,0,0,0,0,0,0,-0.01822]]}]}"##
            }
            return (Data(json.utf8), HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!)
        })
        let result = try await api.snapshot(fileID: ProbeRunner.testFileID, inputTab: "점수 입력 [Score Input]")
        XCTAssertEqual(result, ProbeSnapshot(input: 0, decoded: 0, rating: 0, priority: -0.01822))
        XCTAssertEqual(requests.count, 2)
        XCTAssertTrue(requests[0].url!.path.hasSuffix("!H5"))
        let query = URLComponents(url: requests[1].url!, resolvingAgainstBaseURL: false)!.queryItems!
        XCTAssertEqual(query.filter { $0.name == "ranges" }.compactMap(\.value), ["'점수 입력 [Score Input]'!A5:D5", "'ScoreData'!C2", "'DataM'!J3:S3"])
        XCTAssertTrue(query.contains(URLQueryItem(name: "valueRenderOption", value: "UNFORMATTED_VALUE")))
    }

    func testImportReadRequestsOnlyVersionAndEvaluatedMobileScores() async throws {
        var requests: [URLRequest] = []
        let api = GoogleSheetAPI(token: { "test" }, transport: { request in
            requests.append(request)
            return (Data("{}".utf8), HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!)
        })
        _ = try await api.scoreImportData(fileID: "private-selected-sheet")
        let request = try XCTUnwrap(requests.first)
        XCTAssertEqual(request.httpMethod, "GET")
        let items = URLComponents(url: request.url!, resolvingAgainstBaseURL: false)!.queryItems!
        XCTAssertEqual(items.filter { $0.name == "ranges" }.compactMap(\.value), ["'DevSettings'!C4", "'DataM'!G2:J"])
        XCTAssertTrue(items.contains(URLQueryItem(name: "valueRenderOption", value: "UNFORMATTED_VALUE")))
        XCTAssertEqual(requests.count, 1)
    }

    func testExportReadsEvaluatedLabelsAndFormulaProtectedMobileInputSeparately() async throws {
        var requests: [URLRequest] = []
        let api = GoogleSheetAPI(token: { "test" }, transport: { request in
            requests.append(request)
            return (Data("{}".utf8), HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!)
        })
        _ = try await api.scoreExportData(fileID: "private-selected-sheet", inputTab: "점수 입력 [Score Input]")
        XCTAssertEqual(requests.count, 2)
        let queries = requests.map { URLComponents(url: $0.url!, resolvingAgainstBaseURL: false)!.queryItems! }
        XCTAssertEqual(queries[0].filter { $0.name == "ranges" }.compactMap(\.value), ["'DevSettings'!C4", "'DataM'!G2:J", "'점수 입력 [Score Input]'!A5:D", "'점수 입력 [Score Input]'!H4:I4"])
        XCTAssertTrue(queries[0].contains(URLQueryItem(name: "valueRenderOption", value: "UNFORMATTED_VALUE")))
        XCTAssertTrue(queries[1].contains(URLQueryItem(name: "valueRenderOption", value: "FORMULA")))
        XCTAssertTrue(requests[1].url!.path.hasSuffix("!H4:H"))
        XCTAssertTrue(requests.allSatisfy { $0.httpMethod == "GET" })
    }
    func testProductionWriteOnlyAddressesExplicitMobileRowsIncludingZero() async throws {
        var requests: [URLRequest] = []
        let api = GoogleSheetAPI(token: { "test" }, transport: { request in
            requests.append(request)
            return (Data("{}".utf8), HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!)
        })
        try await api.writeMobileScores(fileID: "private-selected-sheet", inputTab: "Owner's [Score Input]", scores: [5: 9_800_000, 39: 0])
        let body = try XCTUnwrap(JSONSerialization.jsonObject(with: requests[0].httpBody!) as? [String: Any])
        XCTAssertEqual(body["valueInputOption"] as? String, "RAW")
        let data = try XCTUnwrap(body["data"] as? [[String: Any]])
        XCTAssertEqual(data.compactMap { $0["range"] as? String }, ["'Owner''s [Score Input]'!H5", "'Owner''s [Score Input]'!H39"])
        XCTAssertEqual(data.compactMap { $0["values"] as? [[Int]] }, [[[9_800_000]], [[0]]])
        XCTAssertEqual(requests.count, 1)
        do { try await api.writeMobileScores(fileID: "private-selected-sheet", inputTab: "DataM", scores: [5: 1]); XCTFail() } catch {}
        do { try await api.writeMobileScores(fileID: "private-selected-sheet", inputTab: "[Score Input]", scores: [4: 1]); XCTFail() } catch {}
        do { try await api.writeMobileScores(fileID: "private-selected-sheet", inputTab: "[Score Input]", scores: [5: -1]); XCTFail() } catch {}
        XCTAssertEqual(requests.count, 1)
    }

    func testCancellationDuringTokenRefreshPreventsNetworkRequest() async throws {
        var requests = 0
        let work = Task { @MainActor in
            let api = GoogleSheetAPI(token: {
                withUnsafeCurrentTask { $0?.cancel() }
                return "test"
            }, transport: { request in
                requests += 1
                return (Data("{}".utf8), HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!)
            })
            do { _ = try await api.metadata(fileID: "sheet"); return false }
            catch is CancellationError { return true }
            catch { return false }
        }
        let cancelled = await work.value
        XCTAssertTrue(cancelled); XCTAssertEqual(requests, 0)
    }

    func testDefiniteWriteRejectionAndTokenFailureAreMarkedUnsentButTimeoutIsNot() async throws {
        for status in [400, 401, 403, 404, 429, 500] {
            let api = GoogleSheetAPI(token: { "test" }, transport: { request in
                (Data("{}".utf8), HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: ["Retry-After": "120"])!)
            })
            do { try await api.writeMobileScores(fileID: "sheet", inputTab: "[Score Input]", scores: [5: 9_900_000]); XCTFail() }
            catch let error as SheetWriteNotSent { XCTAssertNotEqual(status, 500); XCTAssertEqual((error.underlying as? SheetHTTPError)?.status, status) }
            catch { XCTAssertEqual(status, 500) }
        }
        var calls = 0
        let tokenFailure = GoogleSheetAPI(token: { throw URLError(.notConnectedToInternet) }, transport: { request in
            calls += 1; throw URLError(.timedOut)
        })
        do { try await tokenFailure.writeMobileScores(fileID: "sheet", inputTab: "[Score Input]", scores: [5: 9_900_000]); XCTFail() }
        catch { XCTAssertTrue(error is SheetWriteNotSent) }
        XCTAssertEqual(calls, 0)
        let timeout = GoogleSheetAPI(token: { "test" }, transport: { _ in throw URLError(.timedOut) })
        do { try await timeout.writeMobileScores(fileID: "sheet", inputTab: "[Score Input]", scores: [5: 9_900_000]); XCTFail() }
        catch { XCTAssertFalse(error is SheetWriteNotSent) }
    }

}
