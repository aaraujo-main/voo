#include <tcl.h>

#include <cmath>
#include <sstream>
#include <stdexcept>
#include <string>

#include "tclxx.hpp"

class VooPointBench {
public:
    VooPointBench(double x, double y, std::string name, int id, bool active)
        : m_x(x), m_y(y), m_name(std::move(name)), m_id(id), m_active(active) {}

    VooPointBench()
        : m_x(0.0), m_y(0.0), m_name("point"), m_id(0), m_active(true) {}

    double getX() const { return m_x; }
    void setX(double v) { m_x = v; }

    double getY() const { return m_y; }
    void setY(double v) { m_y = v; }

    const std::string& getName() const { return m_name; }
    void setName(const std::string& v) { m_name = v; }

    int getId() const { return m_id; }
    void setId(int v) { m_id = v; }

    bool isActive() const { return m_active; }
    void setActive(bool v) { m_active = v; }

    double distance() const { return std::sqrt(m_x * m_x + m_y * m_y); }

private:
    double m_x;
    double m_y;
    std::string m_name;
    int m_id;
    bool m_active;
};

namespace tclxx {

template <>
std::string ObjType<VooPointBench>::ToString(const VooPointBench& p) {
    std::ostringstream oss;
    oss << p.getX() << " " << p.getY() << " " << p.getName() << " "
        << p.getId() << " " << (p.isActive() ? "1" : "0");
    return oss.str();
}

template <>
VooPointBench ObjType<VooPointBench>::FromAny(Tcl_Interp* interp, Tcl_Obj* const obj) {
    int objc = 0;
    Tcl_Obj** objv = nullptr;
    if (Tcl_ListObjGetElements(interp, obj, &objc, &objv) != TCL_OK || objc != 5) {
        throw std::runtime_error("Expected list of 5 elements: x y name id active");
    }

    return VooPointBench(
        obj_cast::to<double>(interp, objv[0]),
        obj_cast::to<double>(interp, objv[1]),
        obj_cast::to<std::string>(interp, objv[2]),
        obj_cast::to<int>(interp, objv[3]),
        obj_cast::to<bool>(interp, objv[4])
    );
}

} // namespace tclxx

extern "C" int Point_Init(Tcl_Interp* interp) {
    if (!interp) return TCL_ERROR;

    Tcl_CreateNamespace(interp, "::CppVooPoint", nullptr, nullptr);

    TCLXX_CMD_NEW(interp, "::CppVooPoint::new", VooPointBench,
                     double, double, std::string, int, bool);
    TCLXX_CMD_NEW0(interp, "::CppVooPoint::new()", VooPointBench);

    TCLXX_CMD_GETTER_METHOD(interp, "::CppVooPoint::get.x", &VooPointBench::getX);
    TCLXX_CMD_SETTER_METHOD(interp, "::CppVooPoint::set.x", &VooPointBench::setX);
    TCLXX_CMD_GETTER_METHOD(interp, "::CppVooPoint::distance", &VooPointBench::distance);

    return Tcl_PkgProvideEx(interp, "VooPointCpp", "1.0.0", nullptr);
}