import XCTest
@testable import Mono

final class PawExpressionTests: XCTestCase {
    func testEveryPawExpressionHasItsOwnPoseAndStableIdentity() {
        let expressions = PawExpression.allCases
        XCTAssertEqual(expressions.count, 24)
        XCTAssertEqual(Set(expressions.map(\.id)).count, expressions.count)
        for i in expressions.indices {
            for j in expressions.indices where j > i {
                XCTAssertNotEqual(expressions[i].pose, expressions[j].pose)
            }
        }
    }

    func testCanineEyesUseSmileAndSleepCurvesWithSmallHeadTilts() {
        XCTAssertGreaterThan(PawExpression.beaming.pose.left.closed, 0.9)
        XCTAssertGreaterThan(PawExpression.beaming.pose.left.curve, 0)
        XCTAssertEqual(PawExpression.sleeping.pose.left.closed, 1)
        XCTAssertLessThan(PawExpression.sleeping.pose.left.curve, 0)
        XCTAssertGreaterThan(PawExpression.pleading.pose.left.shine, 0.8)
        for expression in PawExpression.allCases {
            XCTAssertLessThanOrEqual(abs(expression.pose.tilt), 4)
        }
    }

    func testInterruptedPoseBlendPreservesCurrentFaceAndReachesNewExpression() {
        let first = PawExpression.soft.pose
        let next = PawExpression.beaming.pose
        XCTAssertEqual(first.blended(to: next, fraction: 0), first)
        XCTAssertEqual(first.blended(to: next, fraction: 1), next)
        let current = first.blended(to: next, fraction: 0.4)
        let target = PawExpression.pleading.pose
        XCTAssertEqual(current.blended(to: target, fraction: 0), current)
        XCTAssertEqual(current.blended(to: target, fraction: 1), target)
    }

    func testTagsResolveDirectlyToCanineMoodsWithSpecificTagsFirst() {
        XCTAssertEqual(PawTagExpression.resolve(["流行-华语流行", "思念"]), .affectionate)
        XCTAssertEqual(PawTagExpression.resolve(["Dream Pop"]), .dreamy)
        XCTAssertEqual(PawTagExpression.resolve(["Heavy Metal"]), .alert)
        XCTAssertEqual(PawTagExpression.resolve(["睡眠", "氛围"]), .sleeping)
        XCTAssertEqual(PawTagExpression.resolve(["Jazz"]), .curious)
        XCTAssertNil(PawTagExpression.resolve(["Popular playlist", "国语"]))
    }
}
